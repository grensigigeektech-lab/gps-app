import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/screens/map_navigation_controller.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';
import 'helpers/navigation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDirections api;
  late MapNavigationController controller;
  setUp(() {
    api = FakeDirections();
    controller = MapNavigationController(
      directions: api,
      locate: () async => locationResult(),
      mapsConfigured: true,
      autoLocate: false,
    );
  });
  tearDown(() => controller.onClose());

  test('fresh GPS -> geocode -> route -> ready', () async {
    controller.destinationInput.text = 'Surat';
    await controller.search();
    expect(controller.phase.value, NavigationPhase.ready);
    expect(controller.route.value?.distanceMeters, 1500);
    expect(controller.destination.value?.name, 'Destination');
    expect(controller.errorText.value, isEmpty);
  });
  test('disposal ignores a late network completion', () async {
    final delayedApi = FakeDirections()..pending = Completer<NavigationRoute>();
    final closing = MapNavigationController(
      directions: delayedApi,
      locate: () async => locationResult(),
      mapsConfigured: true,
      autoLocate: false,
    );
    closing.destinationInput.text = 'Surat';
    final pending = closing.search();
    await Future<void>.delayed(Duration.zero);
    closing.onClose();
    delayedApi.pending!.complete(FakeDirections.path);
    await pending;
    expect(closing.route.value, isNull);
  });

  test('invalid input does not access GPS or API', () async {
    await controller.search();
    expect(api.searches, 0);
    expect(controller.errorText.value, contains('Enter'));
    expect(controller.isBusy, isFalse);
  });
  test('asks user to disambiguate places before requesting a route', () async {
    api.results = [FakeDirections.destination, FakeDirections.destination];
    controller.destinationInput.text = 'Springfield';
    await controller.search();
    expect(controller.phase.value, NavigationPhase.choosing);
    expect(api.routeCalls, 0);
    await controller.selectDestination(controller.candidates.first);
    expect(controller.phase.value, NavigationPhase.ready);
    expect(controller.candidates, isEmpty);
  });
  test('no route clears old route and supports retry', () async {
    controller.destinationInput.text = 'Surat';
    await controller.search();
    api.failure = const NavigationException(
      NavigationError.noRoute,
      'No driving route',
    );
    await controller.retry();
    expect(controller.route.value, isNull);
    expect(controller.errorText.value, 'No driving route');
    expect(controller.isBusy, isFalse);
    api.failure = null;
    await controller.retry();
    expect(controller.route.value, isNotNull);
  });
  test('editing input invalidates an in-flight route', () async {
    api.pending = Completer<NavigationRoute>();
    controller.destinationInput.text = 'Old destination';
    final search = controller.search();
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase.value, NavigationPhase.routing);
    controller.destinationInput.text = 'New destination';
    controller.destinationChanged('New destination');
    api.pending!.complete(FakeDirections.path);
    await search;
    expect(controller.route.value, isNull);
    expect(controller.destination.value, isNull);
    expect(controller.phase.value, NavigationPhase.idle);
  });
  test('late errors do not overwrite a new search', () async {
    api.pending = Completer<NavigationRoute>();
    controller.destinationInput.text = 'Old';
    final search = controller.search();
    await Future<void>.delayed(Duration.zero);
    controller.destinationChanged('New');
    api.pending!.completeError(
      const NavigationException(NavigationError.network, 'Old error'),
    );
    await search;
    expect(controller.errorText.value, isEmpty);
  });
  test(
    'editing during geocoding ignores late destination candidates',
    () async {
      api.pendingSearch = Completer<List<NavigationDestination>>();
      controller.destinationInput.text = 'Old address';
      final search = controller.search();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase.value, NavigationPhase.searching);
      controller.destinationChanged('New address');
      api.pendingSearch!.complete([FakeDirections.destination]);
      await search;
      expect(controller.destination.value, isNull);
      expect(controller.candidates, isEmpty);
      expect(api.routeCalls, 0);
    },
  );
  test('duplicate submissions do not launch another GPS request', () async {
    controller.onClose();
    final fix = Completer<LocationResult>();
    var gpsCalls = 0;
    controller = MapNavigationController(
      directions: api,
      locate: () {
        gpsCalls++;
        return fix.future;
      },
      mapsConfigured: true,
      autoLocate: false,
    );
    controller.destinationInput.text = 'Surat';
    final search = controller.search();
    await controller.search();
    expect(gpsCalls, 1);
    controller.destinationChanged('New address');
    fix.complete(locationResult());
    await search;
    expect(controller.location.value, isNull);
    expect(api.searches, 0);
  });
  test(
    'route waits for map and style, then survives reload with stale callbacks ignored',
    () async {
      controller.onClose();
      final map = FakeNavigationMap();
      controller = MapNavigationController(
        directions: api,
        map: map,
        locate: () async => locationResult(),
        mapsConfigured: true,
        autoLocate: false,
      );
      controller.destinationInput.text = 'Surat';
      await controller.search();
      expect(map.renders, 0);
      controller.onMapCreated(FakeMapController(), 0);
      expect(map.preparations, 0);
      controller.onStyleLoaded(0);
      await Future<void>.delayed(Duration.zero);
      expect(map.preparations, 1);
      expect(map.displayedRoute, controller.route.value);
      expect(map.fits, 1);
      controller.onMapError(0);
      expect(controller.mapError.value, isNotEmpty);
      await controller.reloadMap();
      controller.onMapError(0);
      controller.onStyleLoaded(0);
      expect(controller.mapError.value, isEmpty);
      expect(controller.mapLoading.value, isTrue);
      controller.onStyleLoaded(1);
      controller.onMapCreated(FakeMapController(), 1);
      await Future<void>.delayed(Duration.zero);
      expect(map.preparations, 2);
      expect(map.displayedRoute, controller.route.value);
      expect(controller.mapLoading.value, isFalse);
    },
  );
  test(
    'queued native updates cannot leave a cancelled route on the map',
    () async {
      controller.onClose();
      final map = FakeNavigationMap();
      controller = MapNavigationController(
        directions: api,
        map: map,
        locate: () async => locationResult(),
        mapsConfigured: true,
        autoLocate: false,
      );
      controller.onMapCreated(FakeMapController(), 0);
      controller.onStyleLoaded(0);
      await Future<void>.delayed(Duration.zero);
      controller.destinationInput.text = 'Surat';
      await controller.search();
      final gate = Completer<void>();
      map.pendingRender = gate;
      final fitting = controller.fitRoute();
      await Future<void>.delayed(Duration.zero);
      controller.destinationChanged('New destination');
      gate.complete();
      await fitting;
      await Future<void>.delayed(Duration.zero);
      expect(map.displayedRoute, isNull);
    },
  );
  for (final error in LocationError.values) {
    test(
      'location $error stops routing and supplies recovery feedback',
      () async {
        controller.onClose();
        controller = MapNavigationController(
          directions: api,
          locate: () async => LocationResult.failure(error, 'Location problem'),
          mapsConfigured: true,
          autoLocate: false,
        );
        controller.destinationInput.text = 'Surat';
        await controller.search();
        expect(api.routeCalls, 0);
        expect(api.searches, 0);
        expect(controller.errorText.value, 'Location problem');
        expect(
          controller.canOpenSettings,
          error == LocationError.serviceDisabled ||
              error == LocationError.permissionPermanentlyDenied,
        );
        expect(controller.isBusy, isFalse);
      },
    );
  }
  test('returns from settings and retries GPS', () async {
    controller.onClose();
    var allowed = false;
    var settingsOpened = false;
    controller = MapNavigationController(
      directions: api,
      locate: () async => allowed
          ? locationResult()
          : LocationResult.failure(LocationError.serviceDisabled, 'Enable GPS'),
      openLocationSettings: () async {
        settingsOpened = true;
        return true;
      },
      mapsConfigured: true,
      autoLocate: false,
    );
    await controller.refreshLocation();
    await controller.openSettings();
    allowed = true;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(settingsOpened, isTrue);
    expect(controller.location.value, isNotNull);
    expect(controller.errorText.value, isEmpty);
  });
  test('failed settings launch is user-actionable', () async {
    controller.onClose();
    controller = MapNavigationController(
      directions: api,
      autoLocate: false,
      openAppSettings: () async => false,
    );
    await controller.openSettings();
    expect(controller.errorText.value, contains('manually'));
  });
}
