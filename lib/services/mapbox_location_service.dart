import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/mapbox_config.dart';

class MapboxLocationInfo {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime timestamp;

  MapboxLocationInfo({
    required this.latitude,
    required this.longitude,
    this.address,
    required this.timestamp,
  });

  String get coordinates => '$latitude, $longitude';

  @override
  String toString() {
    return 'MapboxLocationInfo(latitude: $latitude, longitude: $longitude, address: $address, timestamp: $timestamp)';
  }
}

class MapboxLocationService {
  static MapboxLocationInfo? _currentLocation;
  static bool _isGettingLocation = false;

  static MapboxLocationInfo? get currentLocation => _currentLocation;
  static bool get isGettingLocation => _isGettingLocation;

  static Future<void> initialize() async {
    try {
      // Initialize Mapbox location service
      debugPrint('Mapbox location service initialized');
    } catch (e) {
      debugPrint('Failed to initialize Mapbox location service: $e');
      rethrow;
    }
  }

  static Future<bool> hasLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  static Future<bool> requestLocationPermission() async {
    final result = await Permission.location.request();
    return result.isGranted;
  }

  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await geo.Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking location service: $e');
      return false;
    }
  }

  static Future<MapboxLocationInfo?> getCurrentLocation({
    bool forceRefresh = false,
  }) async {
    if (_isGettingLocation && !forceRefresh) {
      return _currentLocation;
    }

    _isGettingLocation = true;

    try {
      // Check if location service is enabled
      bool serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'Location services are disabled. Please enable them in settings.',
        );
      }

      // Check location permissions
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        final granted = await requestLocationPermission();
        if (!granted) {
          throw Exception('Location permissions are denied');
        }
      }

      // Get current position using geolocator
      geo.Position? position;
      try {
        // Try to get last known location first
        position = await geo.Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint('Error getting last location: $e');
      }

      // If no last location, try to get current location with longer timeout
      if (position == null) {
        try {
          position = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 15),
          );
        } catch (e) {
          debugPrint('Error getting current location: $e');
          throw Exception(
            'Could not determine the current GPS location. Please try again.',
          );
        }
      }

      // Get address from coordinates using Mapbox geocoding
      String? address;
      try {
        address = await _getMapboxAddress(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      } catch (e) {
        debugPrint('Geocoding timeout, using null address: $e');
      }

      final location = MapboxLocationInfo(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        timestamp: DateTime.now(),
      );
      _currentLocation = location;

      debugPrint('Mapbox location retrieved: ${location.coordinates}');
      return location;
    } catch (e) {
      debugPrint('Failed to get Mapbox location: $e');
      rethrow;
    } finally {
      _isGettingLocation = false;
    }
  }

  static Future<String?> _getMapboxAddress(
    double latitude,
    double longitude,
  ) async {
    try {
      // Expanded types to include neighborhood, locality, and region for better coverage
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$longitude,$latitude.json'
          '?access_token=${MapboxConfig.accessToken}&limit=1&types=address,place,neighborhood,locality,region';

      debugPrint('MapboxLocationService: Fetching the current address.');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        if (features.isNotEmpty) {
          final placeName = features.first['place_name'] as String?;
          if (placeName != null && placeName.trim().isNotEmpty) {
            debugPrint('MapboxLocationService geocoding success: $placeName');
            return placeName.trim();
          }
        }
        debugPrint('MapboxLocationService: No address features found.');
      } else {
        debugPrint(
          'MapboxLocationService geocoding failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('MapboxLocationService geocoding error: $e');
    }
    return null;
  }

  static Future<void> startLocationUpdates(
    Function(MapboxLocationInfo) onLocationChanged,
  ) async {
    debugPrint('Location updates not implemented with current SDK version');
    // Note: Real-time location updates would require additional implementation
    // with geolocator's position streams
  }

  static Future<void> stopLocationUpdates() async {
    debugPrint('Location updates stopped');
  }

  static void clearCurrentLocation() {
    _currentLocation = null;
  }

  static void dispose() {
    stopLocationUpdates();
    _currentLocation = null;
  }
}
