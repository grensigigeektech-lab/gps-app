import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotag_camera/services/location_service.dart';

class FakeGps extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0;
  int fixes = 0;
  Object? failure;
  Position position = Position(
    latitude: 0,
    longitude: 0,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requested;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    fixes++;
    expect(locationSettings?.timeLimit, const Duration(seconds: 20));
    if (failure != null) throw failure!;
    return position;
  }
}

void main() {
  late FakeGps gps;
  late GeolocatorPlatform previous;
  setUp(() {
    previous = GeolocatorPlatform.instance;
    gps = FakeGps();
    GeolocatorPlatform.instance = gps;
    LocationService.clearCurrentLocation();
  });
  tearDown(() {
    GeolocatorPlatform.instance = previous;
    LocationService.clearCurrentLocation();
  });
  Future<LocationResult> locate() => LocationService.getCurrentLocationResult(
    forceRefresh: true,
    includeAddress: false,
  );

  test(
    'GPS disabled returns actionable failure without a permission request',
    () async {
      gps.enabled = false;
      expect((await locate()).error, LocationError.serviceDisabled);
      expect(gps.requests, 0);
      expect(gps.fixes, 0);
    },
  );
  test('denial is requested once and handled', () async {
    gps.permission = LocationPermission.denied;
    gps.requested = LocationPermission.denied;
    expect((await locate()).error, LocationError.permissionDenied);
    expect(gps.requests, 1);
    expect(gps.fixes, 0);
  });
  test('permanent denial does not re-prompt', () async {
    gps.permission = LocationPermission.deniedForever;
    expect((await locate()).error, LocationError.permissionPermanentlyDenied);
    expect(gps.requests, 0);
  });
  test(
    'grant during prompt returns fresh GPS, including zero coordinates',
    () async {
      gps.permission = LocationPermission.denied;
      final result = await locate();
      expect(result.success, isTrue);
      expect(result.info!.latitude, 0);
      expect(result.info!.longitude, 0);
      expect(result.info!.timestamp, gps.position.timestamp);
      expect(gps.requests, 1);
      expect(gps.fixes, 1);
      expect(LocationService.isGettingLocation, isFalse);
    },
  );
  test('stale platform fixes are rejected', () async {
    gps.position = Position(
      latitude: 1,
      longitude: 2,
      timestamp: DateTime(2000),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
    expect((await locate()).error, LocationError.timeout);
  });
  test('simultaneous callers share one permission prompt', () async {
    gps.permission = LocationPermission.denied;
    await Future.wait([locate(), locate()]);
    expect(gps.requests, 1);
    expect(LocationService.isGettingLocation, isFalse);
  });
  test('force refresh bypasses cached location', () async {
    await locate();
    await locate();
    expect(gps.fixes, 2);
  });
  test(
    'GPS timeout never falls back to cached/fabricated coordinates',
    () async {
      await locate();
      gps.failure = TimeoutException('timeout');
      final result = await locate();
      expect(result.error, LocationError.timeout);
      expect(result.info, isNull);
      expect(LocationService.currentLocation, isNull);
      expect(LocationService.isGettingLocation, isFalse);
    },
  );
  test('revoked permission is checked even with a cached fix', () async {
    await locate();
    gps.permission = LocationPermission.deniedForever;
    final result = await LocationService.getCurrentLocationResult(
      includeAddress: false,
    );
    expect(result.error, LocationError.permissionPermanentlyDenied);
    expect(result.info, isNull);
  });
  test('service switched off while obtaining GPS is classified', () async {
    gps.failure = const LocationServiceDisabledException();
    expect((await locate()).error, LocationError.serviceDisabled);
  });
  test('platform failures do not leak exception internals', () async {
    gps.failure = StateError('private details');
    final result = await locate();
    expect(result.error, LocationError.unknown);
    expect(result.errorMessage, isNot(contains('private details')));
  });
}
