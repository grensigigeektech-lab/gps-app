import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/screens/map_navigation_controller.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/navigation_service.dart';

final fix = LocationInfo(
  latitude: 21,
  longitude: 72,
  timestamp: DateTime.now(),
);
const target = RouteDestination(name: 'Test city', latitude: 22, longitude: 73);
NavigationRoute makeRoute() => NavigationRoute(
  origin: fix,
  destination: target,
  coordinates: [
    [72, 21],
    [73, 22],
  ],
  distanceMeters: 1000,
  durationSeconds: 120,
);

class FakeNavigation extends NavigationService {
  Completer<List<RouteDestination>>? searchResult;
  Completer<NavigationRoute>? routeResult;
  NavigationException? failure;
  int searchCalls = 0;
  int routeCalls = 0;
  bool disposed = false;
  @override
  Future<List<RouteDestination>> findDestinations(
    String query,
    LocationInfo proximity,
  ) async {
    searchCalls++;
    if (failure != null) throw failure!;
    return searchResult == null ? [target] : searchResult!.future;
  }

  @override
  Future<NavigationRoute> getRoute(
    LocationInfo origin,
    RouteDestination destination,
  ) async {
    routeCalls++;
    if (failure != null) throw failure!;
    return routeResult == null ? makeRoute() : routeResult!.future;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNavigation api;
  late MapNavigationController controller;
  late LocationResult result;
  int locationCalls = 0;
  setUp(() {
    api = FakeNavigation();
    result = LocationResult.success(fix);
    locationCalls = 0;
    controller = MapNavigationController(
      configured: true,
      locateOnInit: false,
      navigationService: api,
      locate: () async {
        locationCalls++;
        return result;
      },
    );
  });
  tearDown(() {
    if (!controller.isClosed) controller.onDelete();
  });

  test(
    'search refreshes GPS, presents choices, then routes on selection',
    () async {
      controller.destinationInput.text = 'Test city';
      await controller.search();
      expect(controller.stage.value, NavigationStage.choosing);
      expect(controller.candidates, [target]);
      expect(api.routeCalls, 0);
      await controller.selectDestination(target);
      expect(locationCalls, 2);
      expect(controller.stage.value, NavigationStage.ready);
      expect(controller.route.value!.destination.name, 'Test city');
    },
  );
  test('blank input never calls GPS or network', () async {
    await controller.search();
    expect(controller.stage.value, NavigationStage.error);
    expect(locationCalls, 0);
    expect(api.searchCalls, 0);
  });
  for (final error in LocationError.values) {
    test(
      'GPS failure $error ends loading and stops downstream requests',
      () async {
        result = LocationResult.failure(error, 'Please retry');
        controller.destinationInput.text = 'Test city';
        await controller.search();
        expect(controller.locationError.value, error);
        expect(controller.busy, isFalse);
        expect(api.searchCalls, 0);
      },
    );
  }
  test('network failure clears stale route and retry recovers', () async {
    await controller.selectDestination(target);
    api.failure = const NavigationException(NavigationError.network);
    await controller.selectDestination(target);
    expect(controller.route.value, isNull);
    expect(controller.message.value, contains('internet'));
    expect(controller.busy, isFalse);
    api.failure = null;
    await controller.retry();
    expect(controller.stage.value, NavigationStage.ready);
  });
  test('late geocoding after an edit is ignored', () async {
    api.searchResult = Completer();
    controller.destinationInput.text = 'First city';
    final pending = controller.search();
    await Future<void>.delayed(Duration.zero);
    expect(controller.stage.value, NavigationStage.searching);
    controller.destinationInput.text = 'Second city';
    controller.destinationChanged('Second city');
    api.searchResult!.complete([target]);
    await pending;
    expect(controller.candidates, isEmpty);
    expect(controller.stage.value, NavigationStage.idle);
  });
  test('late route after an edit is ignored and route stays cleared', () async {
    api.routeResult = Completer();
    final pending = controller.selectDestination(target);
    await Future<void>.delayed(Duration.zero);
    controller.destinationChanged('Second city');
    api.routeResult!.complete(makeRoute());
    await pending;
    expect(controller.route.value, isNull);
    expect(controller.destination.value, isNull);
  });
  test('duplicate submissions while locating are ignored', () async {
    final gps = Completer<LocationResult>();
    controller.onDelete();
    controller = MapNavigationController(
      configured: true,
      locateOnInit: false,
      navigationService: api,
      locate: () => gps.future,
    );
    controller.destinationInput.text = 'Test city';
    final pending = controller.search();
    await controller.search();
    gps.complete(LocationResult.success(fix));
    await pending;
    expect(api.searchCalls, 1);
  });
  test(
    'edit during GPS acquisition cancels selection without overlapping prompts',
    () async {
      final gps = Completer<LocationResult>();
      controller.onDelete();
      controller = MapNavigationController(
        configured: true,
        locateOnInit: false,
        navigationService: api,
        locate: () => gps.future,
      );
      final pending = controller.selectDestination(target);
      controller.destinationChanged('New city');
      await controller.search();
      gps.complete(LocationResult.success(fix));
      await pending;
      expect(api.routeCalls, 0);
      expect(controller.stage.value, NavigationStage.idle);
      expect(controller.route.value, isNull);
    },
  );
  test(
    'closing ignores pending route and disposes network resources',
    () async {
      api.routeResult = Completer();
      final pending = controller.selectDestination(target);
      await Future<void>.delayed(Duration.zero);
      controller.onDelete();
      api.routeResult!.complete(makeRoute());
      await pending;
      expect(api.disposed, isTrue);
      expect(controller.route.value, isNull);
    },
  );
  test(
    'return from location settings refreshes permission and retries',
    () async {
      controller.onDelete();
      int settingsCalls = 0;
      controller = MapNavigationController(
        configured: true,
        locateOnInit: false,
        navigationService: api,
        locate: () async => result,
        openLocationSettings: () async {
          settingsCalls++;
          return true;
        },
      );
      result = LocationResult.failure(LocationError.serviceDisabled, 'GPS off');
      await controller.refreshLocation();
      await controller.openSettings();
      result = LocationResult.success(fix);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(settingsCalls, 1);
      expect(controller.location.value, fix);
      expect(controller.locationError.value, isNull);
    },
  );
  test('map timeout provides retry and closing cancels the timer', () async {
    controller.onInit();
    controller.onMapLoadError(0);
    expect(controller.mapLoading.value, isFalse);
    expect(controller.mapError.value, contains('connection'));
    controller.retryMap();
    expect(controller.mapVersion.value, 1);
    expect(controller.mapLoading.value, isTrue);
    controller.onStyleLoaded(
      0,
    ); // stale callback must not mark the new map ready
    expect(controller.mapLoading.value, isTrue);
    controller.onStyleLoaded(1);
    expect(controller.mapLoading.value, isFalse);
  });
}
