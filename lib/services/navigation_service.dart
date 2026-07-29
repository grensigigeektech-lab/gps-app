import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';

enum NavigationFailureType {
  invalidDestination,
  network,
  noRoute,
  configuration,
}

class NavigationException implements Exception {
  const NavigationException(this.type, this.message);

  final NavigationFailureType type;
  final String message;

  @override
  String toString() => 'NavigationException($type, $message)';
}

class NavigationCoordinate {
  const NavigationCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class NavigationDestination {
  const NavigationDestination({required this.name, required this.coordinate});

  final String name;
  final NavigationCoordinate coordinate;
}

class NavigationRouteResult {
  const NavigationRouteResult({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<NavigationCoordinate> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get distanceLabel {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    final kilometers = distanceMeters / 1000;
    return '${kilometers.toStringAsFixed(kilometers < 100 ? 1 : 0)} km';
  }

  String get durationLabel {
    final totalMinutes = (durationSeconds / 60).ceil();
    if (totalMinutes <= 1) return 'About 1 min';
    if (totalMinutes < 60) return '$totalMinutes min';

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
}

class NavigationService {
  NavigationService({
    http.Client? client,
    String accessToken = MapboxConfig.accessToken,
    Duration requestTimeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _accessToken = accessToken,
       _requestTimeout = requestTimeout;

  final http.Client _client;
  final String _accessToken;
  final Duration _requestTimeout;

  Future<NavigationDestination> geocodeDestination(String input) async {
    final destination = input.trim();
    if (destination.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Enter a destination to create a route.',
      );
    }
    _ensureConfigured();

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
        'autocomplete': 'true',
        'limit': '1',
      },
    );

    final data = await _getJson(uri);
    final features = data['features'];
    if (features is! List || features.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'No matching destination was found. Try a full address or place name.',
      );
    }

    final first = features.first;
    if (first is! Map<String, dynamic>) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination result was incomplete. Try a more specific address.',
      );
    }

    final center = first['center'];
    if (center is! List || center.length < 2) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination result did not contain valid coordinates.',
      );
    }

    final longitude = _finiteDouble(center[0]);
    final latitude = _finiteDouble(center[1]);
    if (latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'The destination result did not contain valid coordinates.',
      );
    }

    final placeName = first['place_name'];
    return NavigationDestination(
      name: placeName is String && placeName.trim().isNotEmpty
          ? placeName.trim()
          : destination,
      coordinate: NavigationCoordinate(
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  Future<NavigationRouteResult> getDrivingRoute({
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
  }) async {
    _ensureConfigured();

    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri =
        Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving/$coordinates',
        ).replace(
          queryParameters: <String, String>{
            'access_token': _accessToken,
            'alternatives': 'false',
            'geometries': 'geojson',
            'overview': 'full',
            'steps': 'false',
          },
        );

    final data = await _getJson(uri);
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'No drivable route could be generated for this destination.',
      );
    }

    final first = routes.first;
    if (first is! Map<String, dynamic>) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route response was incomplete. Please try again.',
      );
    }

    final geometry = first['geometry'];
    final rawCoordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    final distance = _finiteDouble(first['distance']);
    final duration = _finiteDouble(first['duration']);

    if (rawCoordinates is! List || distance == null || duration == null) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route response was incomplete. Please try again.',
      );
    }

    final routeCoordinates = <NavigationCoordinate>[];
    for (final rawCoordinate in rawCoordinates) {
      if (rawCoordinate is! List || rawCoordinate.length < 2) continue;
      final longitude = _finiteDouble(rawCoordinate[0]);
      final latitude = _finiteDouble(rawCoordinate[1]);
      if (longitude == null ||
          latitude == null ||
          longitude.abs() > 180 ||
          latitude.abs() > 90) {
        continue;
      }
      routeCoordinates.add(
        NavigationCoordinate(latitude: latitude, longitude: longitude),
      );
    }

    if (routeCoordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'No usable route geometry was returned. Please try another destination.',
      );
    }

    return NavigationRouteResult(
      coordinates: List<NavigationCoordinate>.unmodifiable(routeCoordinates),
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } on TimeoutException {
      throw const NavigationException(
        NavigationFailureType.network,
        'The map service took too long to respond. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const NavigationException(
        NavigationFailureType.network,
        'Could not reach the map service. Check your internet connection and retry.',
      );
    } catch (_) {
      throw const NavigationException(
        NavigationFailureType.network,
        'Could not reach the map service. Check your internet connection and retry.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const NavigationException(
        NavigationFailureType.configuration,
        'Mapbox rejected the access token. Configure a valid public token and retry.',
      );
    }
    if (response.statusCode == 429) {
      throw const NavigationException(
        NavigationFailureType.network,
        'The map service is temporarily busy. Wait a moment and retry.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const NavigationException(
        NavigationFailureType.network,
        'The map service is unavailable right now. Please retry shortly.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The response is treated as a service failure below.
    }
    throw const NavigationException(
      NavigationFailureType.network,
      'The map service returned an unexpected response. Please retry.',
    );
  }

  void _ensureConfigured() {
    if (_accessToken.isEmpty || _accessToken == 'YOUR_MAPBOX_ACCESS_TOKEN') {
      throw const NavigationException(
        NavigationFailureType.configuration,
        'Map navigation needs a Mapbox access token. Configure MAPBOX_ACCESS_TOKEN first.',
      );
    }
  }

  double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }

  void dispose() => _client.close();
}
