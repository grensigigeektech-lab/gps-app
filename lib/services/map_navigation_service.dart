import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';

enum NavigationFailureType {
  invalidDestination,
  network,
  noRoute,
  configuration,
  server,
}

class NavigationException implements Exception {
  const NavigationException(this.type, this.message);

  final NavigationFailureType type;
  final String message;

  @override
  String toString() => message;
}

class GeocodedDestination {
  const GeocodedDestination({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

class NavigationRoute {
  const NavigationRoute({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<Position> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours hr'
        : '$hours hr $remainingMinutes min';
  }
}

/// Mapbox Geocoding and Directions API adapter used by the navigation flow.
class MapNavigationService {
  MapNavigationService({http.Client? client, String? accessToken})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _accessToken = accessToken ?? MapboxConfig.accessToken;

  final http.Client _client;
  final bool _ownsClient;
  final String _accessToken;

  static const _requestTimeout = Duration(seconds: 15);

  Future<GeocodedDestination> geocodeDestination(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Enter a destination to start navigation.',
      );
    }
    _ensureConfigured();

    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${Uri.encodeComponent(normalizedQuery)}.json',
      {
        'access_token': _accessToken,
        'limit': '1',
        'autocomplete': 'false',
      },
    );
    final payload = await _getJson(uri);
    final features = payload['features'];
    if (features is! List || features.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'We could not find that destination. Check the spelling and try again.',
      );
    }

    final first = features.first;
    if (first is! Map<String, dynamic>) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination result was not valid. Try a more specific address.',
      );
    }
    final center = first['center'];
    if (center is! List ||
        center.length < 2 ||
        center[0] is! num ||
        center[1] is! num) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination did not include usable coordinates.',
      );
    }

    return GeocodedDestination(
      name: (first['place_name'] as String?)?.trim().isNotEmpty == true
          ? (first['place_name'] as String).trim()
          : normalizedQuery,
      longitude: (center[0] as num).toDouble(),
      latitude: (center[1] as num).toDouble(),
    );
  }

  Future<NavigationRoute> getDrivingRoute({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    _ensureConfigured();
    final coordinates = '$originLongitude,$originLatitude;'
        '$destinationLongitude,$destinationLatitude';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coordinates',
      {
        'access_token': _accessToken,
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
      },
    );
    final payload = await _getJson(uri);
    final routes = payload['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'No driving route is available between these locations.',
      );
    }

    final route = routes.first;
    if (route is! Map<String, dynamic> ||
        route['distance'] is! num ||
        route['duration'] is! num) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'Mapbox returned an incomplete route. Try another destination.',
      );
    }
    final geometry = route['geometry'];
    final rawCoordinates =
        geometry is Map<String, dynamic> ? geometry['coordinates'] : null;
    if (rawCoordinates is! List || rawCoordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route did not include a path that can be displayed.',
      );
    }

    final decodedCoordinates = <Position>[];
    for (final item in rawCoordinates) {
      if (item is List &&
          item.length >= 2 &&
          item[0] is num &&
          item[1] is num) {
        decodedCoordinates.add(
          Position(
            (item[0] as num).toDouble(),
            (item[1] as num).toDouble(),
          ),
        );
      }
    }
    if (decodedCoordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route contained no usable map coordinates.',
      );
    }

    return NavigationRoute(
      coordinates: List.unmodifiable(decodedCoordinates),
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final isServerFailure = response.statusCode >= 500;
        throw NavigationException(
          isServerFailure
              ? NavigationFailureType.server
              : NavigationFailureType.network,
          isServerFailure
              ? 'The map service is temporarily unavailable. Try again shortly.'
              : 'The map request failed. Check your connection and try again.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const NavigationException(
          NavigationFailureType.server,
          'The map service returned an unexpected response.',
        );
      }
      return decoded;
    } on NavigationException {
      rethrow;
    } on TimeoutException {
      throw const NavigationException(
        NavigationFailureType.network,
        'The map request timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const NavigationException(
        NavigationFailureType.network,
        'No internet connection. Connect to a network and try again.',
      );
    } on FormatException {
      throw const NavigationException(
        NavigationFailureType.server,
        'The map service returned an unreadable response.',
      );
    } catch (_) {
      throw const NavigationException(
        NavigationFailureType.network,
        'Could not reach the map service. Check your connection and try again.',
      );
    }
  }

  void _ensureConfigured() {
    if (_accessToken.trim().isEmpty ||
        _accessToken == 'YOUR_MAPBOX_ACCESS_TOKEN') {
      throw const NavigationException(
        NavigationFailureType.configuration,
        'Map navigation is not configured. Add a valid Mapbox access token.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
