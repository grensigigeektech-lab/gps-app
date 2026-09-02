import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:geotag_camera/main.dart';
import 'package:geotag_camera/screens/enhanced_camera_screen.dart';
import 'package:geotag_camera/screens/map_navigation_controller.dart';
import 'package:geotag_camera/screens/map_navigation_screen.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/navigation_service.dart';

// No real camera/GPS/network calls in widget tests. Service/platform behavior is
// covered separately; native Mapbox rendering requires an Android/iOS device.
class IdleCameraController extends EnhancedCameraController {
  @override
  // Deliberately avoid native camera/GPS initialization in this test double.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
  });
  tearDown(() {
    Get.reset();
  });

  testWidgets('App smoke test and Map Data entry route', (tester) async {
    Get.put<EnhancedCameraController>(IdleCameraController());
    await tester.pumpWidget(const GeoTagCameraApp());
    await tester.pump();
    expect(find.byType(GeoTagCameraApp), findsOneWidget);
    expect(find.text('Map Data'), findsOneWidget);
    await tester.tap(find.text('Map Data'));
    await tester.pumpAndSettle();
    expect(find.byType(MapNavigationScreen), findsOneWidget);
    expect(find.textContaining('Map access is not configured'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permission error exposes settings and retry actions', (
    tester,
  ) async {
    final controller = Get.put(MapNavigationController(locateOnInit: false));
    controller.message.value = 'GPS is off';
    controller.locationError.value = LocationError.serviceDisabled;
    await tester.pumpWidget(const GetMaterialApp(home: MapNavigationScreen()));
    expect(find.text('GPS is off'), findsOneWidget);
    expect(find.text('Location Settings'), findsOneWidget);
    controller.locationError.value = LocationError.permissionPermanentlyDenied;
    await tester.pump();
    expect(find.text('App Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('route summary labels units and estimate, edit clears it', (
    tester,
  ) async {
    final controller = Get.put(MapNavigationController(locateOnInit: false));
    controller.message.value = null;
    final origin = LocationInfo(
      latitude: 0,
      longitude: 0,
      timestamp: DateTime.now(),
    );
    const target = RouteDestination(
      name: 'Central Station',
      latitude: 1,
      longitude: 1,
    );
    controller.route.value = NavigationRoute(
      origin: origin,
      destination: target,
      coordinates: [
        [0, 0],
        [1, 1],
      ],
      distanceMeters: 2450,
      durationSeconds: 600,
    );
    controller.stage.value = NavigationStage.ready;
    await tester.pumpWidget(const GetMaterialApp(home: MapNavigationScreen()));
    expect(find.text('Central Station'), findsOneWidget);
    expect(find.text('2.5 km · 10 min estimated'), findsOneWidget);
    expect(find.textContaining('excludes live traffic'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Different address');
    await tester.pump();
    expect(find.text('Central Station'), findsNothing);
    expect(controller.route.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading feedback and disabled search are visible', (
    tester,
  ) async {
    final controller = Get.put(MapNavigationController(locateOnInit: false));
    controller.message.value = null;
    controller.stage.value = NavigationStage.searching;
    await tester.pumpWidget(const GetMaterialApp(home: MapNavigationScreen()));
    expect(find.text('Searching destinations…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Search destination',
      ),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact screen with error and larger text remains usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = Get.put(MapNavigationController(locateOnInit: false));
    controller.locationError.value = LocationError.permissionPermanentlyDenied;
    await tester.pumpWidget(
      GetMaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: const MapNavigationScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
