import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';
import '../models/navigation_models.dart';

class NavigationService {
  NavigationService({http.Client? client, String? accessToken})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _accessToken = accessToken ?? MapboxConfig.accessToken;

  final http.Client _client;
  final bool _ownsClient;
  final String _accessToken;

  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<GeocodedDestination> geocodeDestination(String input) async {
    final query = input.trim();
    if (query.length < 3) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Enter a valid destination with at least 3 characters.',
      );
    }
    _ensureMapboxConfigured();

    final uri =
        Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/'
          '${Uri.encodeComponent(query)}.json',
        ).replace(
          queryParameters: <String, String>{
            'access_token': _accessToken,
            'autocomplete': 'true',
            'limit': '1',
            'types': 'address,poi,place,locality,neighborhood,postcode',
          },
        );

    final payload = await _getJson(uri);
    final features = payload['features'];
    if (features is! List || features.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Destination not found. Check the spelling or add a city or postcode.',
      );
    }

    final feature = features.first;
    if (feature is! Map<String, dynamic>) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Destination results were incomplete. Try a more specific address.',
      );
    }

    final center = feature['center'];
    if (center is! List ||
        center.length < 2 ||
        center[0] is! num ||
        center[1] is! num) {
      throw const NavigationException(
        NavigationFailureType.invalidDestination,
        'Destination results did not include valid coordinates.',
      );
    }

    final name = (feature['place_name'] ?? feature['text'])?.toString().trim();
    return GeocodedDestination(
      name: name == null || name.isEmpty ? query : name,
      coordinate: NavigationCoordinate(
        latitude: (center[1] as num).toDouble(),
        longitude: (center[0] as num).toDouble(),
      ),
    );
  }

  Future<NavigationRoute> getDrivingRoute({
    required NavigationCoordinate origin,
    required GeocodedDestination destination,
  }) async {
    _ensureMapboxConfigured();

    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.coordinate.longitude},${destination.coordinate.latitude}';
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

    final payload = await _getJson(uri);
    final routes = payload['routes'];
    if (payload['code'] == 'NoRoute' || routes is! List || routes.isEmpty) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'No driving route could be generated for that destination.',
      );
    }

    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route response was incomplete. Please try again.',
      );
    }

    final geometry = route['geometry'];
    final rawCoordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    final distance = route['distance'];
    final duration = route['duration'];
    if (rawCoordinates is! List ||
        rawCoordinates.length < 2 ||
        distance is! num ||
        duration is! num) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route response did not contain a usable path.',
      );
    }

    final parsedCoordinates = <NavigationCoordinate>[];
    for (final item in rawCoordinates) {
      if (item is List &&
          item.length >= 2 &&
          item[0] is num &&
          item[1] is num) {
        parsedCoordinates.add(
          NavigationCoordinate(
            latitude: (item[1] as num).toDouble(),
            longitude: (item[0] as num).toDouble(),
          ),
        );
      }
    }

    if (parsedCoordinates.length < 2) {
      throw const NavigationException(
        NavigationFailureType.noRoute,
        'The route response did not contain a usable path.',
      );
    }

    return NavigationRoute(
      destination: destination,
      coordinates: List.unmodifiable(parsedCoordinates),
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
    );
  }

  Future<NavigationRoute> findRoute({
    required NavigationCoordinate origin,
    required String destinationInput,
  }) async {
    final destination = await geocodeDestination(destinationInput);
    return getDrivingRoute(origin: origin, destination: destination);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const NavigationException(
          NavigationFailureType.mapConfiguration,
          'Map services could not authenticate. Check the Mapbox access token.',
        );
      }
      if (response.statusCode == 429) {
        throw const NavigationException(
          NavigationFailureType.network,
          'Map services are busy. Wait a moment and try again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const NavigationException(
          NavigationFailureType.network,
          'Map services are unavailable right now. Please try again.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      return decoded;
    } on NavigationException {
      rethrow;
    } on TimeoutException {
      throw const NavigationException(
        NavigationFailureType.network,
        'The request timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const NavigationException(
        NavigationFailureType.network,
        'No network connection. Connect to the internet and try again.',
      );
    } on http.ClientException {
      throw const NavigationException(
        NavigationFailureType.network,
        'Could not reach map services. Check your connection and try again.',
      );
    } on FormatException {
      throw const NavigationException(
        NavigationFailureType.network,
        'Map services returned an unexpected response. Please try again.',
      );
    }
  }

  void _ensureMapboxConfigured() {
    if (_accessToken.isEmpty || _accessToken == 'YOUR_MAPBOX_ACCESS_TOKEN') {
      throw const NavigationException(
        NavigationFailureType.mapConfiguration,
        'Mapbox is not configured. Add MAPBOX_ACCESS_TOKEN at build time.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
