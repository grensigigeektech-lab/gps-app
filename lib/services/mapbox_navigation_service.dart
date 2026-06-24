import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';

class NavigationCoordinate {
  const NavigationCoordinate({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class NavigationDestination {
  const NavigationDestination({
    required this.name,
    required this.coordinate,
  });

  final String name;
  final NavigationCoordinate coordinate;
}

class NavigationRoute {
  NavigationRoute({
    required List<NavigationCoordinate> coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  }) : coordinates = List.unmodifiable(coordinates);

  final List<NavigationCoordinate> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final totalMinutes = (durationSeconds / 60).ceil();
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
}

enum NavigationFailureType {
  invalidInput,
  invalidDestination,
  noRoute,
  network,
  configuration,
  invalidResponse,
}

class NavigationFailure implements Exception {
  const NavigationFailure(this.type, this.message);

  final NavigationFailureType type;
  final String message;

  @override
  String toString() => message;
}

class MapboxNavigationService {
  MapboxNavigationService({
    http.Client? client,
    this.accessToken = MapboxConfig.accessToken,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String accessToken;
  final Duration requestTimeout;

  Future<NavigationDestination> geocodeDestination(String input) async {
    final query = input.trim();
    if (query.length < 2) {
      throw const NavigationFailure(
        NavigationFailureType.invalidInput,
        'Enter a valid destination.',
      );
    }
    _ensureConfigured();

    final uri = Uri(
      scheme: 'https',
      host: 'api.mapbox.com',
      pathSegments: [
        'geocoding',
        'v5',
        'mapbox.places',
        '$query.json',
      ],
      queryParameters: {
        'access_token': accessToken,
        'autocomplete': 'false',
        'limit': '1',
        'language': 'en',
      },
    );

    final data = await _getJson(uri);
    final features = data['features'];
    if (features is! List || features.isEmpty) {
      throw const NavigationFailure(
        NavigationFailureType.invalidDestination,
        'Destination not found. Try a more specific address or place name.',
      );
    }

    final firstFeature = features.first;
    if (firstFeature is! Map<String, dynamic>) {
      throw const NavigationFailure(
        NavigationFailureType.invalidResponse,
        'The destination service returned an invalid response.',
      );
    }

    final center = firstFeature['center'];
    if (center is! List ||
        center.length < 2 ||
        center[0] is! num ||
        center[1] is! num) {
      throw const NavigationFailure(
        NavigationFailureType.invalidResponse,
        'The destination did not include valid coordinates.',
      );
    }

    final name = firstFeature['place_name'];
    return NavigationDestination(
      name: name is String && name.trim().isNotEmpty ? name.trim() : query,
      coordinate: NavigationCoordinate(
        latitude: (center[1] as num).toDouble(),
        longitude: (center[0] as num).toDouble(),
      ),
    );
  }

  Future<NavigationRoute> getDrivingRoute({
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
  }) async {
    _ensureConfigured();

    final coordinates = '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri(
      scheme: 'https',
      host: 'api.mapbox.com',
      pathSegments: [
        'directions',
        'v5',
        'mapbox',
        'driving',
        coordinates,
      ],
      queryParameters: {
        'access_token': accessToken,
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
      },
    );

    final data = await _getJson(uri);
    final code = data['code'];
    final routes = data['routes'];
    if (code == 'NoRoute' ||
        code == 'NoSegment' ||
        routes is! List ||
        routes.isEmpty) {
      throw const NavigationFailure(
        NavigationFailureType.noRoute,
        'No drivable route could be found for this destination.',
      );
    }

    final firstRoute = routes.first;
    if (firstRoute is! Map<String, dynamic>) {
      throw const NavigationFailure(
        NavigationFailureType.invalidResponse,
        'The routing service returned an invalid response.',
      );
    }

    final geometry = firstRoute['geometry'];
    final routeCoordinates =
        geometry is Map<String, dynamic> ? geometry['coordinates'] : null;
    final distance = firstRoute['distance'];
    final duration = firstRoute['duration'];
    if (routeCoordinates is! List ||
        routeCoordinates.length < 2 ||
        distance is! num ||
        duration is! num) {
      throw const NavigationFailure(
        NavigationFailureType.invalidResponse,
        'The route did not include valid geometry or travel details.',
      );
    }

    final parsedCoordinates = <NavigationCoordinate>[];
    for (final coordinate in routeCoordinates) {
      if (coordinate is! List ||
          coordinate.length < 2 ||
          coordinate[0] is! num ||
          coordinate[1] is! num) {
        throw const NavigationFailure(
          NavigationFailureType.invalidResponse,
          'The route contained invalid coordinates.',
        );
      }
      parsedCoordinates.add(
        NavigationCoordinate(
          latitude: (coordinate[1] as num).toDouble(),
          longitude: (coordinate[0] as num).toDouble(),
        ),
      );
    }

    return NavigationRoute(
      coordinates: parsedCoordinates,
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(requestTimeout);
    } on TimeoutException {
      throw const NavigationFailure(
        NavigationFailureType.network,
        'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const NavigationFailure(
        NavigationFailureType.network,
        'Unable to reach Mapbox. Check your connection and try again.',
      );
    } catch (_) {
      throw const NavigationFailure(
        NavigationFailureType.network,
        'A network error occurred. Check your connection and try again.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const NavigationFailure(
        NavigationFailureType.configuration,
        'Map services are not configured correctly.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const NavigationFailure(
        NavigationFailureType.network,
        'Map services are temporarily unavailable. Try again shortly.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Handled below as an invalid service response.
    }
    throw const NavigationFailure(
      NavigationFailureType.invalidResponse,
      'Map services returned an invalid response. Try again.',
    );
  }

  void _ensureConfigured() {
    if (accessToken.isEmpty || accessToken == 'YOUR_MAPBOX_ACCESS_TOKEN') {
      throw const NavigationFailure(
        NavigationFailureType.configuration,
        'Map services are not configured. Add a Mapbox access token.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
