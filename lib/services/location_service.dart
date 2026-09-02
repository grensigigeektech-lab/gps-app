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

  LocationResult.success(LocationInfo this.info)
    : error = null,
      errorMessage = null;

  LocationResult.failure(LocationError this.error, String this.errorMessage)
    : info = null;
}

/// Shared GPS/permission implementation for both camera and navigation.
class LocationService {
  static LocationInfo? _currentLocation;
  static int _pendingRequests = 0;
  static Future<LocationPermission>? _permissionRequest;

  static LocationInfo? get currentLocation => _currentLocation;
  static bool get isGettingLocation => _pendingRequests > 0;

  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<LocationPermission> _ensurePermission() {
    return _permissionRequest ??= _checkAndRequestPermission().whenComplete(() {
      _permissionRequest = null;
    });
  }

  static Future<LocationPermission> _checkAndRequestPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.denied
        ? Geolocator.requestPermission()
        : permission;
  }

  static Future<bool> requestLocationPermission() async {
    final permission = await _ensurePermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<LocationResult> getCurrentLocationResult({
    bool forceRefresh = false,
    bool includeAddress = true,
  }) async {
    _pendingRequests++;
    try {
      // Never return a cached fix before rechecking service and permission.
      if (!await isLocationServiceEnabled()) {
        return _failure(LocationError.serviceDisabled);
      }
      final permission = await _ensurePermission();
      if (permission == LocationPermission.deniedForever) {
        return _failure(LocationError.permissionPermanentlyDenied);
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return _failure(LocationError.permissionDenied);
      }

      final cached = _currentLocation;
      if (!forceRefresh &&
          cached != null &&
          DateTime.now().difference(cached.timestamp) <
              const Duration(seconds: 30)) {
        return LocationResult.success(cached);
      }

      // A navigation origin must be real and fresh. No fixed-coordinate or
      // last-known fallback when the current GPS fix fails.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        return _failure(LocationError.unknown);
      }
      if (DateTime.now().difference(position.timestamp) >
          const Duration(minutes: 2)) {
        return _failure(LocationError.timeout);
      }
      final address = includeAddress
          ? await _getMapboxAddress(position.latitude, position.longitude)
          : null;
      final location = LocationInfo(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        timestamp: position.timestamp,
      );
      _currentLocation = location;
      return LocationResult.success(location);
    } on TimeoutException {
      return _failure(LocationError.timeout);
    } on LocationServiceDisabledException {
      return _failure(LocationError.serviceDisabled);
    } on PermissionDeniedException {
      return _failure(LocationError.permissionDenied);
    } catch (_) {
      return _failure(LocationError.unknown);
    } finally {
      _pendingRequests--;
    }
  }

  static LocationResult _failure(LocationError error) {
    _currentLocation = null;
    final message = switch (error) {
      LocationError.serviceDisabled =>
        'GPS is turned off. Enable Location Services in Settings, then retry.',
      LocationError.permissionDenied =>
        'Location access was denied. Tap Retry to allow location access.',
      LocationError.permissionPermanentlyDenied =>
        'Location access is blocked. Allow it in App Settings, then retry.',
      LocationError.timeout =>
        'Could not get a GPS fix. Move to an open area and retry.',
      LocationError.unknown =>
        'Could not determine your location. Please retry.',
    };
    return LocationResult.failure(error, message);
  }

  static Future<LocationInfo?> getCurrentLocation({
    bool forceRefresh = false,
  }) async {
    final result = await getCurrentLocationResult(forceRefresh: forceRefresh);
    if (result.success) return result.info;
    throw Exception(result.errorMessage);
  }

  static Future<String?> _getMapboxAddress(
    double latitude,
    double longitude,
  ) async {
    if (!MapboxConfig.isConfigured) return null;
    final client = http.Client();
    try {
      final uri = Uri.https(
        'api.mapbox.com',
        '/geocoding/v5/mapbox.places/$longitude,$latitude.json',
        {
          'access_token': MapboxConfig.accessToken,
          'limit': '1',
          'types': 'address,place,neighborhood,locality,region',
        },
      );
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>;
      if (features.isEmpty) return null;
      final name = features.first['place_name'] as String?;
      return name == null || name.trim().isEmpty ? null : name.trim();
    } catch (_) {
      // Address lookup is optional; failure must not discard a valid GPS fix.
      return null;
    } finally {
      client.close();
    }
  }

  static void clearCurrentLocation() => _currentLocation = null;
}
