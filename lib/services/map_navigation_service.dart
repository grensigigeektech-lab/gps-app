import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';
import 'location_service.dart';

enum MapNavigationErrorType {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  locationUnavailable,
  invalidDestination,
  noRoute,
  network,
  mapboxConfiguration,
  mapUnavailable,
  unknown,
}

class MapNavigationException implements Exception {
  final MapNavigationErrorType type;
  final String message;
  final Object? cause;

  const MapNavigationException(this.type, this.message, {this.cause});

  @override
  String toString() => message;
}

class NavigationCoordinate {
  final double latitude;
  final double longitude;

  const NavigationCoordinate({required this.latitude, required this.longitude});

  factory NavigationCoordinate.fromLocationInfo(LocationInfo info) {
    return NavigationCoordinate(
      latitude: info.latitude,
      longitude: info.longitude,
    );
  }

  String get mapboxValue => '$longitude,$latitude';

  bool get isValid {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }
}

class DestinationSearchResult {
  final NavigationCoordinate coordinate;
  final String placeName;

  const DestinationSearchResult({
    required this.coordinate,
    required this.placeName,
  });
}

class NavigationRoute {
  final NavigationCoordinate origin;
  final NavigationCoordinate destination;
  final String destinationName;
  final List<NavigationCoordinate> routePoints;
  final double distanceMeters;
  final double durationSeconds;

  const NavigationRoute({
    required this.origin,
    required this.destination,
    required this.destinationName,
    required this.routePoints,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }

    final kilometers = distanceMeters / 1000;
    return '${kilometers.toStringAsFixed(kilometers >= 10 ? 0 : 1)} km';
  }

  String get formattedDuration {
    final totalMinutes = math.max(1, (durationSeconds / 60).round());

    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }
}

class MapNavigationService {
  static const Duration _requestTimeout = Duration(seconds: 15);

  static Future<NavigationCoordinate> getCurrentCoordinate({
    bool forceRefresh = false,
  }) async {
    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: forceRefresh,
    );

    if (result.success && result.info != null) {
      return NavigationCoordinate.fromLocationInfo(result.info!);
    }

    throw _locationException(result);
  }

  static Future<NavigationRoute> createRouteToDestination(
    String destinationInput, {
    http.Client? client,
  }) async {
    _normalizedDestination(destinationInput);
    _ensureMapboxToken();

    final effectiveClient = client ?? http.Client();

    try {
      final origin = await getCurrentCoordinate(forceRefresh: true);
      final destination = await geocodeDestination(
        destinationInput,
        client: effectiveClient,
      );

      return getRoute(
        origin: origin,
        destination: destination,
        client: effectiveClient,
      );
    } finally {
      if (client == null) {
        effectiveClient.close();
      }
    }
  }

  static Future<DestinationSearchResult> geocodeDestination(
    String destinationInput, {
    http.Client? client,
  }) async {
    final query = _normalizedDestination(destinationInput);

    _ensureMapboxToken();

    final effectiveClient = client ?? http.Client();
    final encodedQuery = Uri.encodeComponent(query);
    final uri =
        Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$encodedQuery.json',
        ).replace(
          queryParameters: {
            'access_token': MapboxConfig.accessToken,
            'limit': '1',
            'types': 'address,poi,place,locality,neighborhood,region,country',
          },
        );

    try {
      final response = await effectiveClient.get(uri).timeout(_requestTimeout);
      return parseGeocodingResponse(response.statusCode, response.body);
    } on TimeoutException catch (error) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Destination lookup timed out. Check your connection and try again.',
        cause: error,
      );
    } on MapNavigationException {
      rethrow;
    } catch (error) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Could not search that destination. Check your connection and try again.',
        cause: error,
      );
    } finally {
      if (client == null) {
        effectiveClient.close();
      }
    }
  }

  static Future<NavigationRoute> getRoute({
    required NavigationCoordinate origin,
    required DestinationSearchResult destination,
    http.Client? client,
  }) async {
    if (!origin.isValid || !destination.coordinate.isValid) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'The route contains invalid coordinates.',
      );
    }

    _ensureMapboxToken();

    final effectiveClient = client ?? http.Client();
    final coordinates =
        '${origin.mapboxValue};${destination.coordinate.mapboxValue}';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coordinates',
      {
        'access_token': MapboxConfig.accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
        'alternatives': 'false',
      },
    );

    try {
      final response = await effectiveClient.get(uri).timeout(_requestTimeout);
      return parseDirectionsResponse(
        statusCode: response.statusCode,
        body: response.body,
        origin: origin,
        destination: destination,
      );
    } on TimeoutException catch (error) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Route generation timed out. Check your connection and try again.',
        cause: error,
      );
    } on MapNavigationException {
      rethrow;
    } catch (error) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Could not generate a route. Check your connection and try again.',
        cause: error,
      );
    } finally {
      if (client == null) {
        effectiveClient.close();
      }
    }
  }

  @visibleForTesting
  static DestinationSearchResult parseGeocodingResponse(
    int statusCode,
    String body,
  ) {
    if (statusCode == 401 || statusCode == 403) {
      throw const MapNavigationException(
        MapNavigationErrorType.mapboxConfiguration,
        'Mapbox access token was rejected. Update the token before using navigation.',
      );
    }

    final data = _decodeJson(body);

    if (statusCode < 200 || statusCode >= 300) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Destination lookup failed. Try again in a moment.',
        cause: data,
      );
    }

    final features = data['features'];
    if (features is! List || features.isEmpty) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'No matching destination found. Check the address and try again.',
      );
    }

    final feature = features.first;
    if (feature is! Map<String, dynamic>) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'The destination result was not usable. Try a more specific address.',
      );
    }

    final center = feature['center'];
    if (center is! List || center.length < 2) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'The destination did not include coordinates.',
      );
    }

    final longitude = _readDouble(
      center[0],
      errorType: MapNavigationErrorType.invalidDestination,
      message: 'The destination coordinates were invalid.',
    );
    final latitude = _readDouble(
      center[1],
      errorType: MapNavigationErrorType.invalidDestination,
      message: 'The destination coordinates were invalid.',
    );
    final placeName = (feature['place_name'] as String?)?.trim();
    final coordinate = NavigationCoordinate(
      latitude: latitude,
      longitude: longitude,
    );

    if (!coordinate.isValid) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'The destination coordinates were invalid.',
      );
    }

    return DestinationSearchResult(
      coordinate: coordinate,
      placeName: placeName?.isNotEmpty == true ? placeName! : 'Destination',
    );
  }

  @visibleForTesting
  static NavigationRoute parseDirectionsResponse({
    required int statusCode,
    required String body,
    required NavigationCoordinate origin,
    required DestinationSearchResult destination,
  }) {
    if (statusCode == 401 || statusCode == 403) {
      throw const MapNavigationException(
        MapNavigationErrorType.mapboxConfiguration,
        'Mapbox access token was rejected. Update the token before using navigation.',
      );
    }

    final data = _decodeJson(body);

    final code = data['code'] as String?;
    if (code == 'NoRoute' || code == 'NoSegment') {
      throw MapNavigationException(
        MapNavigationErrorType.noRoute,
        'No route could be generated for that destination.',
        cause: data,
      );
    }

    if (statusCode < 200 || statusCode >= 300) {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Route generation failed. Try again in a moment.',
        cause: data,
      );
    }

    final routes = data['routes'];
    if (code != null && code != 'Ok') {
      throw MapNavigationException(
        MapNavigationErrorType.network,
        'Route generation failed. Try again in a moment.',
        cause: data,
      );
    }

    if (routes is! List || routes.isEmpty) {
      throw const MapNavigationException(
        MapNavigationErrorType.noRoute,
        'No route could be generated for that destination.',
      );
    }

    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      throw const MapNavigationException(
        MapNavigationErrorType.noRoute,
        'The route response was not usable.',
      );
    }

    final distance = _readDouble(
      route['distance'],
      errorType: MapNavigationErrorType.noRoute,
      message: 'The route response included invalid distance data.',
    );
    final duration = _readDouble(
      route['duration'],
      errorType: MapNavigationErrorType.noRoute,
      message: 'The route response included invalid duration data.',
    );
    if (!distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        duration < 0) {
      throw const MapNavigationException(
        MapNavigationErrorType.noRoute,
        'The route response included invalid travel metrics.',
      );
    }
    final geometry = route['geometry'];
    final coordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;

    if (coordinates is! List || coordinates.length < 2) {
      throw const MapNavigationException(
        MapNavigationErrorType.noRoute,
        'The route did not include enough points to draw on the map.',
      );
    }

    final routePoints = coordinates
        .map<NavigationCoordinate>((coordinate) {
          if (coordinate is! List || coordinate.length < 2) {
            throw const MapNavigationException(
              MapNavigationErrorType.noRoute,
              'The route included invalid coordinates.',
            );
          }

          return NavigationCoordinate(
            latitude: _readDouble(
              coordinate[1],
              errorType: MapNavigationErrorType.noRoute,
              message: 'The route included invalid coordinates.',
            ),
            longitude: _readDouble(
              coordinate[0],
              errorType: MapNavigationErrorType.noRoute,
              message: 'The route included invalid coordinates.',
            ),
          );
        })
        .toList(growable: false);

    if (routePoints.any((coordinate) => !coordinate.isValid)) {
      throw const MapNavigationException(
        MapNavigationErrorType.noRoute,
        'The route included invalid coordinates.',
      );
    }

    return NavigationRoute(
      origin: origin,
      destination: destination.coordinate,
      destinationName: destination.placeName,
      routePoints: routePoints,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  static MapNavigationException _locationException(LocationResult result) {
    switch (result.error) {
      case LocationError.serviceDisabled:
        return MapNavigationException(
          MapNavigationErrorType.serviceDisabled,
          result.errorMessage ??
              'Location services are disabled. Turn on GPS and try again.',
        );
      case LocationError.permissionDenied:
        return MapNavigationException(
          MapNavigationErrorType.permissionDenied,
          result.errorMessage ??
              'Location permission is required to build a route.',
        );
      case LocationError.permissionPermanentlyDenied:
        return MapNavigationException(
          MapNavigationErrorType.permissionPermanentlyDenied,
          result.errorMessage ??
              'Location permission is permanently denied. Open Settings to allow access.',
        );
      case LocationError.timeout:
        return MapNavigationException(
          MapNavigationErrorType.locationUnavailable,
          result.errorMessage ??
              'Could not determine your current GPS location.',
        );
      case LocationError.unknown:
      case null:
        return MapNavigationException(
          MapNavigationErrorType.unknown,
          result.errorMessage ?? 'Could not determine your current location.',
        );
    }
  }

  static void _ensureMapboxToken() {
    if (!MapboxConfig.hasValidAccessToken) {
      throw const MapNavigationException(
        MapNavigationErrorType.mapboxConfiguration,
        'Mapbox access token is not configured. Add a valid token to enable navigation.',
      );
    }
  }

  static String _normalizedDestination(String destinationInput) {
    final destination = destinationInput.trim();
    if (destination.isEmpty) {
      throw const MapNavigationException(
        MapNavigationErrorType.invalidDestination,
        'Enter a destination to start navigation.',
      );
    }
    return destination;
  }

  static Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall through to the shared response error below.
    }

    throw const MapNavigationException(
      MapNavigationErrorType.network,
      'The server returned an unreadable response. Try again later.',
    );
  }

  static double _readDouble(
    Object? value, {
    required MapNavigationErrorType errorType,
    required String message,
  }) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }

    throw MapNavigationException(errorType, message);
  }
}
