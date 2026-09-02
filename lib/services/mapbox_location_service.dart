import 'location_service.dart';

// Preserve the camera's public location API while sharing one permission/GPS
// implementation. Both screens acquire foreground fixes on explicit actions.
typedef MapboxLocationInfo = LocationInfo;

class MapboxLocationService {
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
  static void clearCurrentLocation() => LocationService.clearCurrentLocation();
  static void dispose() => clearCurrentLocation();
}
