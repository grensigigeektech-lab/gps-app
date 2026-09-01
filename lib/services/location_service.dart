import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/mapbox_config.dart';

class LocationInfo {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime timestamp;

  LocationInfo({
    required this.latitude,
    required this.longitude,
    this.address,
    required this.timestamp,
  });

  String get coordinates => '$latitude, $longitude';

  @override
  String toString() {
    return 'LocationInfo(lat: $latitude, lng: $longitude, address: $address)';
  }
}

enum LocationError {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timeout,
  unknown,
}

class LocationResult {
  final LocationInfo? info;
  final LocationError? error;
  final String? errorMessage;

  bool get success => info != null;

  LocationResult.success(this.info) : error = null, errorMessage = null;

  LocationResult.failure(this.error, this.errorMessage) : info = null;
}

class LocationService {
  static LocationInfo? _currentLocation;
  static int _activeRequests = 0;
  static Future<Position>? _positionRequest;

  static LocationInfo? get currentLocation => _currentLocation;
  static bool get isGettingLocation => _activeRequests > 0;

  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> requestLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  /// Every request requires a fresh GPS fix. Cached or invented positions must
  /// never be presented as a user's current location or used as a route origin.
  /// Concurrent callers share only the in-flight native position request.
  static Future<LocationResult> getCurrentLocationResult({
    bool forceRefresh = false,
    bool reverseGeocode = true,
  }) async {
    _activeRequests++;
    try {
      if (!await isLocationServiceEnabled()) return _disabled;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failure(
          LocationError.permissionPermanentlyDenied,
          'Location access is blocked. Open app settings to allow location access.',
        );
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return LocationResult.failure(
          LocationError.permissionDenied,
          'Location access was denied. Tap Retry to allow access.',
        );
      }
      final request = _positionRequest ??= Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      ).timeout(const Duration(seconds: 22));
      late final Position position;
      try {
        position = await request;
      } finally {
        if (identical(_positionRequest, request)) _positionRequest = null;
      }
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        return LocationResult.failure(
          LocationError.unknown,
          'GPS returned an invalid location. Please try again.',
        );
      }
      final address = reverseGeocode
          ? await _getMapboxAddress(position.latitude, position.longitude)
          : null;
      _currentLocation = LocationInfo(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        timestamp: position.timestamp,
      );
      return LocationResult.success(_currentLocation);
    } on LocationServiceDisabledException {
      return _disabled;
    } on PermissionDeniedException {
      return LocationResult.failure(
        LocationError.permissionDenied,
        'Location access was denied. Tap Retry to allow access.',
      );
    } on TimeoutException {
      return LocationResult.failure(
        LocationError.timeout,
        'Could not get a GPS fix. Move to an open area and try again.',
      );
    } catch (_) {
      return LocationResult.failure(
        LocationError.unknown,
        'Could not determine your location. Check GPS and permissions, then retry.',
      );
    } finally {
      _activeRequests--;
    }
  }

  static LocationResult get _disabled => LocationResult.failure(
    LocationError.serviceDisabled,
    'GPS is turned off. Enable Location Services in settings, then retry.',
  );

  static Future<LocationInfo?> getCurrentLocation({
    bool forceRefresh = false,
  }) async {
    final result = await getCurrentLocationResult(forceRefresh: forceRefresh);
    if (result.success) return result.info;
    throw Exception(result.errorMessage ?? 'Failed to get location');
  }

  static Future<String?> _getMapboxAddress(
    double latitude,
    double longitude,
  ) async {
    if (!MapboxConfig.isConfigured) return null;
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.mapbox.com', '/search/geocode/v6/reverse', {
              'longitude': '$longitude',
              'latitude': '$latitude',
              'access_token': MapboxConfig.accessToken,
              'limit': '1',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final features = data['features'] as List;
      if (features.isEmpty) return null;
      final properties = features.first['properties'] as Map;
      final name = properties['full_address'] ?? properties['name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (_) {
      // Reverse geocoding is optional; GPS must remain available offline.
      return null;
    } finally {
      client.close();
    }
  }

  static void clearCurrentLocation() => _currentLocation = null;
}
