import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:geotag_camera/screens/map_navigation_controller.dart';
import 'package:geotag_camera/screens/map_navigation_screen.dart';
import 'package:geotag_camera/services/location_service.dart';

import 'helpers/navigation_fakes.dart' show FakeDirections, locationResult;

void main() {
  late MapNavigationController controller;
  setUp(() => Get.testMode = true);
  tearDown(() async {
    await Get.deleteAll(force: true);
    Get.reset();
  });

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    MapNavigationController? instance,
  }) async {
    // Create Futures inside the widget test's FakeAsync zone, not in setUp.
    controller =
        instance ??
        MapNavigationController(
          directions: FakeDirections(),
          locate: () async => locationResult(),
          mapsConfigured: true,
          autoLocate: false,
        );
    Get.put(controller);
    await tester.pumpWidget(
      GetMaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(375, 812),
            textScaler: TextScaler.linear(scale),
          ),
          child: MapNavigationScreen(
            mapBuilder: (_) => const ColoredBox(color: Colors.grey),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'destination form shows validation and route summary',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Find driving route'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a destination address or place.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Surat');
      await tester.tap(find.text('Find driving route'));
      await tester.pumpAndSettle();
      expect(
        find.text('1.5 km · 10 min estimated driving time'),
        findsOneWidget,
      );
      expect(find.text('Show entire route'), findsOneWidget);
      expect(find.text('Your location'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await Get.deleteAll(force: true);
      Get.reset();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows a progress state and disables repeated submissions',
    (tester) async {
      final pending = Completer<LocationResult>();
      final delayedController = MapNavigationController(
        directions: FakeDirections(),
        locate: () => pending.future,
        mapsConfigured: true,
        autoLocate: false,
      );
      await mount(tester, instance: delayedController);
      await tester.enterText(find.byType(TextField), 'Surat');
      await tester.tap(find.text('Find driving route'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      pending.complete(
        LocationResult.failure(
          LocationError.permissionPermanentlyDenied,
          'Allow location in settings',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await Get.deleteAll(force: true);
      Get.reset();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'compact screen and large text do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, scale: 2);
      controller.destinationInput.text = 'Surat';
      await controller.search();
      await tester.pumpAndSettle();
      expect(controller.route.value, isNotNull);
      expect(tester.takeException(), isNull);
      await Get.deleteAll(force: true);
      Get.reset();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('refits the route after available map space changes', (
    tester,
  ) async {
    final map = FakeNavigationMap();
    final instance = MapNavigationController(
      directions: FakeDirections(),
      map: map,
      locate: () async => locationResult(),
      mapsConfigured: true,
      autoLocate: false,
    );
    await mount(tester, instance: instance);
    controller.onMapCreated(FakeMapController(), 0);
    controller.onStyleLoaded(0);
    await tester.pumpAndSettle();
    controller.destinationInput.text = 'Surat';
    await controller.search();
    await tester.pumpAndSettle();
    final fitsBeforeResize = map.fits;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(map.fits, greaterThan(fitsBeforeResize));
    expect(tester.takeException(), isNull);
    await Get.deleteAll(force: true);
    Get.reset();
  });
}
