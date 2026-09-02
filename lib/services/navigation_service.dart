import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';
import 'location_service.dart';

enum NavigationError {
  invalidDestination,
  destinationNotFound,
  noRoute,
  network,
  timeout,
  configuration,
  rateLimited,
  unavailable,
  invalidResponse,
}

class NavigationException implements Exception {
  const NavigationException(this.error);
  final NavigationError error;

  String get message => switch (error) {
    NavigationError.invalidDestination =>
      'Enter an address or city (up to 256 characters, without semicolons).',
    NavigationError.destinationNotFound =>
      'No matching destination found. Try a full address or a nearby city.',
    NavigationError.noRoute =>
      'No driving route connects these locations. Try another destination.',
    NavigationError.network =>
      'Could not connect. Check your internet connection and retry.',
    NavigationError.timeout =>
      'The map service took too long to respond. Please retry.',
    NavigationError.configuration =>
      'Map access is not configured. Please contact the app administrator.',
    NavigationError.rateLimited =>
      'The map service is busy. Please wait a moment and retry.',
    NavigationError.unavailable =>
      'The map service is temporarily unavailable. Please retry later.',
    NavigationError.invalidResponse =>
      'The map service returned incomplete data. Please retry.',
  };
}

class RouteDestination {
  const RouteDestination({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
  final String name;
  final double latitude;
  final double longitude;
}

class NavigationRoute {
  NavigationRoute({
    required this.origin,
    required this.destination,
    required List<List<double>> coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  }) : coordinates = List.unmodifiable(
         coordinates.map((point) => List<double>.unmodifiable(point)),
       );

  final LocationInfo origin;
  final RouteDestination destination;
  // GeoJSON ordering: longitude, latitude. Includes every route vertex.
  final List<List<double>> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get durationLabel {
    final minutes = (durationSeconds / 60).ceil();
    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '$minutes min';
    final remainder = minutes % 60;
    return '${minutes ~/ 60} hr${remainder == 0 ? '' : ' $remainder min'}';
  }
}

/// Mapbox forward geocoding and driving directions, using existing HTTP/Mapbox
/// dependencies. Results stay in memory (temporary geocoding, no persistence).
class NavigationService {
  NavigationService({
    String accessToken = MapboxConfig.accessToken,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _accessToken = accessToken,
       _clientFactory = clientFactory ?? http.Client.new;

  final String _accessToken;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout;
  final Set<http.Client> _pendingClients = {};

  static String? validateDestination(String query) {
    final text = query.trim();
    if (text.isEmpty ||
        text.length > 256 ||
        text.contains(';') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(text) ||
        text.split(RegExp(r'\s+')).length > 20) {
      return const NavigationException(
        NavigationError.invalidDestination,
      ).message;
    }
    return null;
  }

  Future<List<RouteDestination>> findDestinations(
    String query,
    LocationInfo proximity,
  ) async {
    if (validateDestination(query) != null) {
      throw const NavigationException(NavigationError.invalidDestination);
    }
    final data = await _get('/search/geocode/v6/forward', {
      'q': query.trim(),
      'autocomplete': 'false',
      'limit': '5',
      'proximity': '${proximity.longitude},${proximity.latitude}',
    });
    try {
      final features = data['features'] as List<dynamic>;
      if (features.isEmpty) {
        throw const NavigationException(NavigationError.destinationNotFound);
      }
      return features
          .map((feature) {
            final properties = feature['properties'] as Map<String, dynamic>;
            final geometry = feature['geometry'] as Map<String, dynamic>;
            if (geometry['type'] != 'Point') throw const FormatException();
            final coordinate = _coordinate(geometry['coordinates']);
            final name = properties['full_address'] ?? properties['name'];
            if (name is! String || name.trim().isEmpty) {
              throw const FormatException();
            }
            return RouteDestination(
              name: name.trim(),
              longitude: coordinate[0],
              latitude: coordinate[1],
            );
          })
          .toList(growable: false);
    } on NavigationException {
      rethrow;
    } catch (_) {
      throw const NavigationException(NavigationError.invalidResponse);
    }
  }

  Future<NavigationRoute> getRoute(
    LocationInfo origin,
    RouteDestination destination,
  ) async {
    _coordinate([origin.longitude, origin.latitude]);
    _coordinate([destination.longitude, destination.latitude]);
    final data = await _get(
      '/directions/v5/mapbox/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}',
      {'geometries': 'geojson', 'overview': 'full', 'steps': 'false'},
    );
    if (data['code'] == 'NoRoute' || data['code'] == 'NoSegment') {
      throw const NavigationException(NavigationError.noRoute);
    }
    try {
      if (data['code'] != 'Ok') throw const FormatException();
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw const NavigationException(NavigationError.noRoute);
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      if (geometry['type'] != 'LineString') throw const FormatException();
      final coordinates = (geometry['coordinates'] as List<dynamic>)
          .map(_coordinate)
          .toList(growable: false);
      if (coordinates.length < 2) throw const FormatException();
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();
      if (!distance.isFinite ||
          distance < 0 ||
          !duration.isFinite ||
          duration < 0) {
        throw const FormatException();
      }
      return NavigationRoute(
        origin: origin,
        destination: destination,
        coordinates: coordinates,
        distanceMeters: distance,
        durationSeconds: duration,
      );
    } on NavigationException {
      rethrow;
    } catch (_) {
      throw const NavigationException(NavigationError.invalidResponse);
    }
  }

  static List<double> _coordinate(dynamic raw) {
    if (raw is! List || raw.length < 2 || raw[0] is! num || raw[1] is! num) {
      throw const NavigationException(NavigationError.invalidResponse);
    }
    final longitude = (raw[0] as num).toDouble();
    final latitude = (raw[1] as num).toDouble();
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude.abs() > 180 ||
        latitude.abs() > 90) {
      throw const NavigationException(NavigationError.invalidResponse);
    }
    return [longitude, latitude];
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    if (!_accessToken.startsWith('pk.')) {
      throw const NavigationException(NavigationError.configuration);
    }
    final client = _clientFactory();
    _pendingClients.add(client);
    try {
      final uri = Uri.https('api.mapbox.com', path, {
        ...query,
        'access_token': _accessToken,
      });
      final response = await client.get(uri).timeout(requestTimeout);
      switch (response.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw const NavigationException(NavigationError.configuration);
        case 429:
          throw const NavigationException(NavigationError.rateLimited);
        case 400:
        case 422:
          throw const NavigationException(NavigationError.invalidDestination);
        default:
          throw const NavigationException(NavigationError.unavailable);
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on NavigationException {
      rethrow;
    } on TimeoutException {
      throw const NavigationException(NavigationError.timeout);
    } on http.ClientException {
      throw const NavigationException(NavigationError.network);
    } on SocketException {
      throw const NavigationException(NavigationError.network);
    } on IOException {
      throw const NavigationException(NavigationError.network);
    } catch (_) {
      throw const NavigationException(NavigationError.invalidResponse);
    } finally {
      _pendingClients.remove(client);
      client.close();
    }
  }

  void cancelPending() {
    for (final client in _pendingClients.toList()) {
      client.close();
    }
    _pendingClients.clear();
  }

  void dispose() => cancelPending();
}
