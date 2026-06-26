import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';
import '../models/map_navigation.dart';

enum MapNavigationFailureType {
  invalidDestination,
  destinationNotFound,
  noRoute,
  network,
  configuration,
  invalidResponse,
}

class MapNavigationException implements Exception {
  const MapNavigationException(this.type, this.message);

  final MapNavigationFailureType type;
  final String message;

  @override
  String toString() => message;
}

class MapNavigationService {
  MapNavigationService({
    http.Client? client,
    String accessToken = MapboxConfig.accessToken,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _accessToken = accessToken;

  final http.Client _client;
  final bool _ownsClient;
  final String _accessToken;

  Future<NavigationDestination> geocodeDestination(String query) async {
    final destination = query.trim();
    if (destination.isEmpty) {
      throw const MapNavigationException(
        MapNavigationFailureType.invalidDestination,
        'Enter a destination to start navigation.',
      );
    }
    _validateConfiguration();

    final uri = Uri(
      scheme: 'https',
      host: 'api.mapbox.com',
      pathSegments: <String>[
        'geocoding',
        'v5',
        'mapbox.places',
        '$destination.json',
      ],
      queryParameters: <String, String>{
        'access_token': _accessToken,
        'autocomplete': 'false',
        'limit': '1',
        'types': 'address,poi,place,locality,neighborhood',
      },
    );

    final body = await _getJson(uri);
    final features = body['features'];
    if (features is! List || features.isEmpty) {
      throw const MapNavigationException(
        MapNavigationFailureType.destinationNotFound,
        'We could not find that destination. Check the spelling and try again.',
      );
    }

    final feature = features.first;
    if (feature is! Map<String, dynamic>) {
      throw _invalidResponse();
    }
    final center = feature['center'];
    if (center is! List || center.length < 2) {
      throw _invalidResponse();
    }
    final longitude = center[0];
    final latitude = center[1];
    if (longitude is! num || latitude is! num) {
      throw _invalidResponse();
    }

    return NavigationDestination(
      name: (feature['place_name'] as String?)?.trim().isNotEmpty == true
          ? (feature['place_name'] as String).trim()
          : destination,
      coordinate: NavigationCoordinate(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
    );
  }

  Future<NavigationRoute> getDrivingRoute({
    required NavigationCoordinate origin,
    required NavigationDestination destination,
  }) async {
    _validateConfiguration();

    final coordinates =
        '${origin.mapboxValue};'
        '${destination.coordinate.mapboxValue}';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coordinates',
      <String, String>{
        'access_token': _accessToken,
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
      },
    );

    final body = await _getJson(uri);
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const MapNavigationException(
        MapNavigationFailureType.noRoute,
        'No drivable route is available for that destination.',
      );
    }

    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      throw _invalidResponse();
    }
    final distance = route['distance'];
    final duration = route['duration'];
    final geometry = route['geometry'];
    final routeCoordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    if (distance is! num ||
        duration is! num ||
        routeCoordinates is! List ||
        routeCoordinates.length < 2) {
      throw _invalidResponse();
    }

    final parsedCoordinates = <NavigationCoordinate>[];
    for (final coordinate in routeCoordinates) {
      if (coordinate is! List || coordinate.length < 2) {
        throw _invalidResponse();
      }
      final longitude = coordinate[0];
      final latitude = coordinate[1];
      if (longitude is! num || latitude is! num) {
        throw _invalidResponse();
      }
      parsedCoordinates.add(
        NavigationCoordinate(
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        ),
      );
    }

    return NavigationRoute(
      destination: destination,
      coordinates: List.unmodifiable(parsedCoordinates),
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const MapNavigationException(
        MapNavigationFailureType.network,
        'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const MapNavigationException(
        MapNavigationFailureType.network,
        'Unable to connect. Check your internet connection and try again.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const MapNavigationException(
        MapNavigationFailureType.configuration,
        'Map services are not configured correctly. Please contact support.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MapNavigationException(
        MapNavigationFailureType.network,
        response.statusCode >= 500
            ? 'Map services are temporarily unavailable. Try again shortly.'
            : 'The map request failed. Check your connection and try again.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Converted to the user-facing response error below.
    }
    throw _invalidResponse();
  }

  void _validateConfiguration() {
    if (!_accessToken.startsWith('pk.')) {
      throw const MapNavigationException(
        MapNavigationFailureType.configuration,
        'Map services are not configured. Add a valid Mapbox access token.',
      );
    }
  }

  MapNavigationException _invalidResponse() => const MapNavigationException(
    MapNavigationFailureType.invalidResponse,
    'Map services returned an unexpected response. Please try again.',
  );

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
