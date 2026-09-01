import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';

class RouteCoordinate {
  const RouteCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static RouteCoordinate fromJson(Object? value) {
    if (value is! List ||
        value.length < 2 ||
        value[0] is! num ||
        value[1] is! num) {
      throw const FormatException('Invalid coordinates');
    }
    final point = RouteCoordinate(
      (value[1] as num).toDouble(),
      (value[0] as num).toDouble(),
    );
    if (!point.isValid) throw const FormatException('Invalid coordinates');
    return point;
  }
}

class NavigationDestination {
  const NavigationDestination({required this.name, required this.coordinate});
  final String name;
  final RouteCoordinate coordinate;
}

class NavigationRoute {
  NavigationRoute({
    required List<RouteCoordinate> coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  }) : coordinates = List.unmodifiable(coordinates);

  final List<RouteCoordinate> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get durationLabel {
    final minutes = (durationSeconds / 60).ceil().clamp(1, 1000000);
    if (minutes < 60) return '$minutes min';
    final remainder = minutes % 60;
    return '${minutes ~/ 60} hr${remainder == 0 ? '' : ' $remainder min'}';
  }
}

enum NavigationError {
  invalidDestination,
  noDestination,
  noRoute,
  network,
  timeout,
  configuration,
  rateLimited,
  service,
  invalidResponse,
}

class NavigationException implements Exception {
  const NavigationException(this.error, this.message);
  final NavigationError error;
  final String message;
  @override
  String toString() => message;
}

/// Uses the existing Mapbox account and HTTP dependency. Results stay in memory:
/// Mapbox temporary geocoding results must not be persisted.
class MapboxDirectionsService {
  MapboxDirectionsService({
    http.Client? client,
    String? accessToken,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _accessToken = accessToken ?? MapboxConfig.accessToken;

  final http.Client _client;
  final String _accessToken;
  final Duration timeout;

  static String? validateDestination(String input) {
    final text = input.trim();
    if (text.isEmpty) return 'Enter a destination address or place.';
    if (text.length > 256) return 'Keep the destination under 257 characters.';
    if (text.length < 2 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(text) ||
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
      return 'Enter a valid address or place name.';
    }
    return null;
  }

  Future<List<NavigationDestination>> searchDestinations(
    String input, {
    RouteCoordinate? proximity,
  }) async {
    final validation = validateDestination(input);
    if (validation != null) {
      throw NavigationException(NavigationError.invalidDestination, validation);
    }
    final data = await _get('/search/geocode/v6/forward', {
      'q': input.trim(),
      'limit': '5',
      'autocomplete': 'false',
      if (proximity != null && proximity.isValid)
        'proximity': '${proximity.longitude},${proximity.latitude}',
    });
    try {
      final features = data['features'];
      if (features is! List) throw const FormatException();
      if (features.isEmpty) {
        throw const NavigationException(
          NavigationError.noDestination,
          'No destination found. Try a street address and city.',
        );
      }
      final destinations = <NavigationDestination>[];
      for (final feature in features) {
        if (feature is! Map) throw const FormatException();
        final properties = feature['properties'];
        final geometry = feature['geometry'];
        if (properties is! Map ||
            geometry is! Map ||
            geometry['type'] != 'Point') {
          throw const FormatException();
        }
        final label = properties['full_address'] ?? properties['name'];
        if (label is! String || label.trim().isEmpty) {
          throw const FormatException();
        }
        destinations.add(
          NavigationDestination(
            name: label.trim(),
            coordinate: RouteCoordinate.fromJson(geometry['coordinates']),
          ),
        );
      }
      return destinations;
    } on FormatException {
      throw _invalidResponse;
    }
  }

  Future<NavigationRoute> getRoute(
    RouteCoordinate origin,
    RouteCoordinate destination,
  ) async {
    if (!origin.isValid || !destination.isValid) {
      throw const NavigationException(
        NavigationError.invalidDestination,
        'The location coordinates are invalid. Please try again.',
      );
    }
    final data = await _get(
      '/directions/v5/mapbox/driving/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}',
      {
        'geometries': 'geojson',
        'overview': 'full',
        'alternatives': 'false',
        'steps': 'false',
      },
    );
    if (data['code'] == 'NoRoute' || data['code'] == 'NoSegment') {
      throw _noRoute;
    }
    if (data['code'] != 'Ok') throw _invalidResponse;
    try {
      final routes = data['routes'];
      if (routes is! List) throw const FormatException();
      if (routes.isEmpty) throw _noRoute;
      final route = routes.first;
      if (route is! Map) throw const FormatException();
      final geometry = route['geometry'];
      final distance = route['distance'];
      final duration = route['duration'];
      if (geometry is! Map ||
          geometry['type'] != 'LineString' ||
          geometry['coordinates'] is! List ||
          distance is! num ||
          duration is! num ||
          !distance.isFinite ||
          distance < 0 ||
          !duration.isFinite ||
          duration < 0) {
        throw const FormatException();
      }
      final points = (geometry['coordinates'] as List)
          .map(RouteCoordinate.fromJson)
          .toList();
      if (points.length < 2) throw _noRoute;
      return NavigationRoute(
        coordinates: points,
        distanceMeters: distance.toDouble(),
        durationSeconds: duration.toDouble(),
      );
    } on FormatException {
      throw _invalidResponse;
    }
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    if (!_accessToken.startsWith('pk.')) {
      throw const NavigationException(
        NavigationError.configuration,
        'Maps are not configured. Please contact the app administrator.',
      );
    }
    try {
      final response = await _client
          .get(
            Uri.https('api.mapbox.com', path, {
              ...query,
              'access_token': _accessToken,
            }),
          )
          .timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const NavigationException(
          NavigationError.configuration,
          'Map access is unavailable. Please contact the app administrator.',
        );
      }
      if (response.statusCode == 429) {
        throw const NavigationException(
          NavigationError.rateLimited,
          'Maps are busy right now. Wait a moment, then try again.',
        );
      }
      if (response.statusCode >= 500) {
        throw const NavigationException(
          NavigationError.service,
          'The map service is temporarily unavailable. Please try again.',
        );
      }
      if (response.statusCode != 200) {
        throw const NavigationException(
          NavigationError.service,
          'The map request could not be completed. Check the destination and retry.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } on TimeoutException {
      throw const NavigationException(
        NavigationError.timeout,
        'The map request timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      // Never expose a raw exception or URL containing the access token.
      throw const NavigationException(
        NavigationError.network,
        'Could not connect to maps. Check your internet connection and retry.',
      );
    } on FormatException {
      throw _invalidResponse;
    }
  }

  static const _noRoute = NavigationException(
    NavigationError.noRoute,
    'No driving route is available between these locations. Try another destination.',
  );
  static const _invalidResponse = NavigationException(
    NavigationError.invalidResponse,
    'The map service returned an incomplete result. Please try again.',
  );

  void dispose() => _client.close();
}
