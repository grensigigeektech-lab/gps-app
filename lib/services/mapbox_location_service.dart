import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;

import 'location_service.dart';

// Retain the camera-facing API while sharing one permission/GPS implementation.
typedef MapboxLocationInfo = LocationInfo;

class MapboxLocationService {
  static StreamSubscription<geo.Position>? _subscription;
  static MapboxLocationInfo? get currentLocation =>
      LocationService.currentLocation;
  static bool get isGettingLocation => LocationService.isGettingLocation;

  static Future<void> initialize() async {}
  static Future<bool> hasLocationPermission() =>
      LocationService.hasLocationPermission();
  static Future<bool> requestLocationPermission() =>
      LocationService.requestLocationPermission();
  static Future<bool> isLocationServiceEnabled() =>
      LocationService.isLocationServiceEnabled();
  static Future<MapboxLocationInfo?> getCurrentLocation({
    bool forceRefresh = false,
  }) => LocationService.getCurrentLocation(forceRefresh: forceRefresh);

  static Future<void> startLocationUpdates(
    void Function(MapboxLocationInfo) onLocationChanged,
  ) async {
    await stopLocationUpdates();
    _subscription =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 25,
          ),
        ).listen(
          (position) {
            onLocationChanged(
              LocationInfo(
                latitude: position.latitude,
                longitude: position.longitude,
                timestamp: position.timestamp,
              ),
            );
          },
          onError: (Object _) {
            // A later explicit GPS request surfaces permission/service errors to UI.
          },
        );
  }

  static Future<void> stopLocationUpdates() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static void clearCurrentLocation() => LocationService.clearCurrentLocation();
  static void dispose() {
    unawaited(stopLocationUpdates());
    clearCurrentLocation();
  }
}
