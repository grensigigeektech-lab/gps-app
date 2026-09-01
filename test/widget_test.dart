import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:geotag_camera/main.dart';
import 'package:geotag_camera/routes/app_routes.dart';
import 'package:geotag_camera/screens/enhanced_camera_screen.dart';
import 'package:geotag_camera/screens/map_navigation_controller.dart';

void main() {
  testWidgets('camera screen keeps its entry point and opens map navigation', (
    tester,
  ) async {
    Get.testMode = true;
    Get.put<EnhancedCameraController>(
      EnhancedCameraController(autoInitialize: false),
    );
    Get.put<MapNavigationController>(
      MapNavigationController(autoLocate: false, mapsConfigured: false),
    );
    addTearDown(() async {
      await Get.deleteAll(force: true);
      Get.reset();
    });
    await tester.pumpWidget(const GeoTagCameraApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('PHOTO'), findsOneWidget);
    expect(find.text('Map Data'), findsOneWidget);
    await tester.tap(find.text('Map Data'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(Get.currentRoute, AppRoutes.mapNavigation);
    expect(find.text('Map navigation'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await Get.deleteAll(force: true);
  });
}
