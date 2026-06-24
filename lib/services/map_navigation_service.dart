import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';
import '../models/navigation_models.dart';

class MapNavigationService {
  static const String _mapboxHost = 'api.mapbox.com';
  static const Duration _requestTimeout = Duration(seconds: 15);

  static bool get hasConfiguredAccessToken {
    final token = MapboxConfig.accessToken.trim();
    return token.isNotEmpty && token != 'YOUR_MAPBOX_ACCESS_TOKEN';
  }

  static Future<NavigationCoordinate> geocodeDestination(String input) async {
    final query = input.trim();
    if (query.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Enter a destination to build a route.',
      );
    }

    _ensureAccessToken();

    final uri = Uri(
      scheme: 'https',
      host: _mapboxHost,
      pathSegments: <String>[
        'geocoding',
        'v5',
        'mapbox.places',
        '$query.json',
      ],
      queryParameters: <String, String>{
        'access_token': MapboxConfig.accessToken,
        'autocomplete': 'false',
        'limit': '1',
      },
    );

    final data = await _getJson(uri);
    final features = data['features'];
    if (features is! List || features.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'No matching destination was found. Try a more specific address.',
      );
    }

    return coordinateFromMapboxFeature(
      Map<String, dynamic>.from(features.first as Map),
      fallbackLabel: query,
    );
  }

  static Future<NavigationRoute> fetchRoute({
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
  }) async {
    _ensureAccessToken();

    final uri = Uri.https(
      _mapboxHost,
      '/directions/v5/mapbox/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}',
      <String, String>{
        'access_token': MapboxConfig.accessToken,
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
      },
    );

    final data = await _getJson(uri);
    final code = data['code']?.toString();
    final routes = data['routes'];

    if (code == 'NoRoute' || routes is! List || routes.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'No route could be generated for this destination.',
      );
    }

    return routeFromMapboxRoute(
      Map<String, dynamic>.from(routes.first as Map),
      origin: origin,
      destination: destination,
    );
  }

  static NavigationCoordinate coordinateFromMapboxFeature(
    Map<String, dynamic> feature, {
    required String fallbackLabel,
  }) {
    final geometry = feature['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;

    if (coordinates is! List || coordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination result did not include usable coordinates.',
      );
    }

    final longitude = _toDouble(coordinates[0]);
    final latitude = _toDouble(coordinates[1]);
    if (latitude == null || longitude == null) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination coordinates were invalid.',
      );
    }

    final placeName = feature['place_name']?.toString().trim();
    return NavigationCoordinate(
      latitude: latitude,
      longitude: longitude,
      label: placeName == null || placeName.isEmpty ? fallbackLabel : placeName,
    );
  }

  static NavigationRoute routeFromMapboxRoute(
    Map<String, dynamic> route, {
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
  }) {
    final geometry = route['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;

    if (coordinates is! List || coordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The generated route did not include enough path data.',
      );
    }

    final path = <NavigationCoordinate>[];
    for (final item in coordinates) {
      if (item is! List || item.length < 2) {
        continue;
      }

      final longitude = _toDouble(item[0]);
      final latitude = _toDouble(item[1]);
      if (latitude == null || longitude == null) {
        continue;
      }

      path.add(
        NavigationCoordinate(
          latitude: latitude,
          longitude: longitude,
          label: '',
        ),
      );
    }

    if (path.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The generated route did not include enough path data.',
      );
    }

    return NavigationRoute(
      origin: origin,
      destination: destination,
      path: path,
      distanceMeters: _toDouble(route['distance']) ?? 0,
      durationSeconds: _toDouble(route['duration']) ?? 0,
    );
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await http.get(uri).timeout(_requestTimeout);
      final decoded = json.decode(response.body);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }

      debugPrint(
          'Mapbox request failed: ${response.statusCode} ${response.body}');
      final message = data['message']?.toString();
      throw NavigationException(
        response.statusCode == 401 || response.statusCode == 403
            ? NavigationFailureType.missingToken
            : NavigationFailureType.network,
        message == null || message.isEmpty
            ? 'Mapbox could not complete the request. Please try again.'
            : message,
      );
    } on NavigationException {
      rethrow;
    } on TimeoutException {
      throw const NavigationException(
        NavigationFailureType.network,
        'The route request timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const NavigationException(
        NavigationFailureType.network,
        'Network connection failed. Check your internet connection and try again.',
      );
    } on FormatException {
      throw const NavigationException(
        NavigationFailureType.network,
        'Mapbox returned an unexpected response. Please try again.',
      );
    } catch (error) {
      debugPrint('Unexpected Mapbox navigation error: $error');
      throw const NavigationException(
        NavigationFailureType.unknown,
        'Something went wrong while building the route.',
      );
    }
  }

  static void _ensureAccessToken() {
    if (!hasConfiguredAccessToken) {
      throw const NavigationException(
        NavigationFailureType.missingToken,
        'Mapbox access token is missing. Add it before using navigation.',
      );
    }
  }

  static double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
