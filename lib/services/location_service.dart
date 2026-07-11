import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

  LocationResult.success(this.info)
      : error = null,
        errorMessage = null;

  LocationResult.failure(this.error, this.errorMessage) : info = null;
}

class LocationService {
  static LocationInfo? _currentLocation;
  static bool _isGettingLocation = false;

  static LocationInfo? get currentLocation => _currentLocation;
  static bool get isGettingLocation => _isGettingLocation;

  /// Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request location permission — returns true if granted
  static Future<bool> requestLocationPermission() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  static Future<LocationResult> getCurrentLocationResult(
      {bool forceRefresh = false}) async {
    if (_isGettingLocation && !forceRefresh) {
      if (_currentLocation != null) {
        return LocationResult.success(_currentLocation);
      }
    }

    _isGettingLocation = true;

    try {
      // 1. Check service
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failure(
          LocationError.serviceDisabled,
          'GPS is turned off. Please enable Location Services in Settings.',
        );
      }

      // 2. Check / request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return LocationResult.failure(
          LocationError.permissionDenied,
          'Location access was denied. Tap "Enable" to grant permission.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failure(
          LocationError.permissionPermanentlyDenied,
          'Location is permanently denied. Open Settings to allow access.',
        );
      }

      // 3. Get position
      Position? position;
      try {
        debugPrint('Attempting to get last known position...');
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          debugPrint('Found last known position: ${position.latitude}, ${position.longitude}');
        }
      } catch (e) {
        debugPrint('Error getting last known position: $e');
      }

      // Fetch a fresh position
      try {
        debugPrint('Fetching fresh position with high accuracy...');
        final fresh = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 20),
        );
        position = fresh;
        debugPrint('Fresh position obtained: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('Fresh position failed: $e');
        final lastKnownIsStale = position != null &&
            position.timestamp.isBefore(
              DateTime.now().subtract(const Duration(minutes: 5)),
            );
        if (position == null || lastKnownIsStale) {
          return LocationResult.failure(
            LocationError.timeout,
            'Could not get a current GPS fix. Move to an open area and retry.',
          );
        } else {
          debugPrint('Proceeding with last known position.');
        }
      }

      // 4. Geocode via Mapbox
      String? address;
      try {
        address = await _getMapboxAddress(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
      } catch (e) {
        debugPrint('Geocoding failed: $e');
      }

      _currentLocation = LocationInfo(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        timestamp: DateTime.now(),
      );

      return LocationResult.success(_currentLocation);
    } catch (e) {
      debugPrint('LocationService error: $e');
      return LocationResult.failure(
        LocationError.unknown,
        'Could not access your location. Check Location Services and try again.',
      );
    } finally {
      _isGettingLocation = false;
    }
  }

  /// Legacy helper used by older callers — wraps the result version
  static Future<LocationInfo?> getCurrentLocation({
    bool forceRefresh = false,
  }) async {
    final result = await getCurrentLocationResult(forceRefresh: forceRefresh);
    if (result.success) return result.info;
    throw Exception(result.errorMessage ?? 'Failed to get location');
  }

  static Future<String?> _getMapboxAddress(
      double latitude, double longitude) async {
    try {
      // Expanded types to include neighborhood, locality, and region for better coverage
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$longitude,$latitude.json'
          '?access_token=${MapboxConfig.accessToken}&limit=1&types=address,place,neighborhood,locality,region';

      debugPrint('Fetching address from Mapbox');
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        
        if (features.isNotEmpty) {
          final placeName = features.first['place_name'] as String?;
          if (placeName != null && placeName.trim().isNotEmpty) {
            debugPrint('Mapbox geocoding success: $placeName');
            return placeName.trim();
          } else {
            debugPrint('Mapbox geocoding: Found feature but place_name was empty.');
          }
        } else {
          debugPrint('Mapbox geocoding: No features found in response.');
        }
      } else {
        debugPrint('Mapbox geocoding failed. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('Mapbox geocoding exception: $e');
    }
    return null;
  }

  static void clearCurrentLocation() {
    _currentLocation = null;
  }
}
