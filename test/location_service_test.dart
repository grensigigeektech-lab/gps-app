import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotag_camera/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  var enabled = true;
  var permission = LocationPermission.whileInUse;
  var requestedPermission = LocationPermission.whileInUse;
  var failPosition = false;
  var positionTimestamp = DateTime.now();
  Completer<int>? permissionGate;
  final calls = <String>[];
  setUp(() {
    enabled = true;
    permission = LocationPermission.whileInUse;
    requestedPermission = LocationPermission.whileInUse;
    failPosition = false;
    positionTimestamp = DateTime.now();
    permissionGate = null;
    calls.clear();
    LocationService.clearCurrentLocation();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return enabled;
            case 'checkPermission':
              return permission.index;
            case 'requestPermission':
              return permissionGate?.future ?? requestedPermission.index;
            case 'getCurrentPosition':
              if (failPosition) {
                throw PlatformException(code: 'POSITION_UNAVAILABLE');
              }
              return {
                'latitude': 21.1,
                'longitude': 72.2,
                'timestamp': positionTimestamp.millisecondsSinceEpoch,
                'accuracy': 5.0,
                'altitude': 0.0,
                'altitude_accuracy': 0.0,
                'heading': 0.0,
                'heading_accuracy': 0.0,
                'speed': 0.0,
                'speed_accuracy': 0.0,
                'is_mocked': false,
              };
            default:
              throw StateError('Unexpected native call: ${call.method}');
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    LocationService.clearCurrentLocation();
  });
  test('disabled GPS stops before permission or position requests', () async {
    enabled = false;
    final result = await LocationService.getCurrentLocationResult(
      reverseGeocode: false,
    );
    expect(result.error, LocationError.serviceDisabled);
    expect(calls, ['isLocationServiceEnabled']);
  });
  test('denied permission is requested and handled without GPS', () async {
    permission = LocationPermission.denied;
    requestedPermission = LocationPermission.denied;
    final result = await LocationService.getCurrentLocationResult(
      reverseGeocode: false,
    );
    expect(result.error, LocationError.permissionDenied);
    expect(calls, contains('requestPermission'));
    expect(calls, isNot(contains('getCurrentPosition')));
  });
  test('permanent denial never requests permission again', () async {
    permission = LocationPermission.deniedForever;
    final result = await LocationService.getCurrentLocationResult(
      reverseGeocode: false,
    );
    expect(result.error, LocationError.permissionPermanentlyDenied);
    expect(calls, isNot(contains('requestPermission')));
  });
  test('uses a fresh fix without network reverse-geocoding', () async {
    final result = await LocationService.getCurrentLocationResult(
      reverseGeocode: false,
    );
    expect(result.success, isTrue);
    expect(result.info!.latitude, 21.1);
    expect(result.info!.longitude, 72.2);
    expect(result.info!.address, isNull);
    expect(calls, contains('getCurrentPosition'));
    expect(calls, isNot(contains('getLastKnownPosition')));
    expect(LocationService.isGettingLocation, isFalse);
  });
  test(
    'concurrent callers share the permission prompt and native GPS fix',
    () async {
      permission = LocationPermission.denied;
      permissionGate = Completer<int>();
      final first = LocationService.getCurrentLocationResult(
        reverseGeocode: false,
      );
      final second = LocationService.getCurrentLocationResult(
        reverseGeocode: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call == 'requestPermission').length, 1);
      permissionGate!.complete(LocationPermission.whileInUse.index);
      final results = await Future.wait([first, second]);
      expect(results.every((result) => result.success), isTrue);
      expect(calls.where((call) => call == 'getCurrentPosition').length, 1);
      expect(LocationService.isGettingLocation, isFalse);
    },
  );
  test('rejects an old fix returned by the native provider', () async {
    positionTimestamp = DateTime.now().subtract(const Duration(minutes: 10));
    final result = await LocationService.getCurrentLocationResult(
      reverseGeocode: false,
    );
    expect(result.error, LocationError.timeout);
    expect(result.errorMessage, contains('old location'));
    expect(result.info, isNull);
  });
  test(
    'failed refresh never substitutes cached or fabricated coordinates',
    () async {
      await LocationService.getCurrentLocationResult(reverseGeocode: false);
      failPosition = true;
      final result = await LocationService.getCurrentLocationResult(
        reverseGeocode: false,
      );
      expect(result.success, isFalse);
      expect(result.info, isNull);
      expect(result.error, isNotNull);
      expect(LocationService.isGettingLocation, isFalse);
    },
  );
}
