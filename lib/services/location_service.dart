import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../config/mapbox_config.dart';
import 'mapbox_directions_service.dart';

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
  static Future<LocationPermission>? _permissionRequest;

  static LocationInfo? get currentLocation => _currentLocation;
  static bool get isGettingLocation => _activeRequests > 0;

  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> requestLocationPermission() async {
    final permission = await _ensurePermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<LocationPermission> _ensurePermission() async {
    // Camera and navigation must not open overlapping native permission prompts.
    final request = _permissionRequest ??= _checkAndRequestPermission();
    try {
      return await request;
    } finally {
      if (identical(request, _permissionRequest)) _permissionRequest = null;
    }
  }

  static Future<LocationPermission> _checkAndRequestPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.denied
        ? Geolocator.requestPermission()
        : permission;
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
      final permission = await _ensurePermission();
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
      if (DateTime.now().difference(position.timestamp) >
          const Duration(minutes: 2)) {
        return LocationResult.failure(
          LocationError.timeout,
          'GPS returned an old location. Move to an open area and retry.',
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
    final geocoder = MapboxDirectionsService(
      timeout: const Duration(seconds: 8),
    );
    try {
      return await geocoder.reverseGeocode(
        RouteCoordinate(latitude, longitude),
      );
    } catch (_) {
      // Reverse geocoding is optional; GPS must remain available offline.
      return null;
    } finally {
      geocoder.dispose();
    }
  }

  static void clearCurrentLocation() => _currentLocation = null;
}
