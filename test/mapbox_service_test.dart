import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/mapbox_service.dart';
import 'package:geotag_camera/services/navigation_service.dart';

class RecordingPoints extends Fake implements PointAnnotationManager {
  final List<PointAnnotationOptions> points = [];
  @override
  Future<void> deleteAll() async => points.clear();
  @override
  Future<PointAnnotation> create(PointAnnotationOptions options) async {
    points.add(options);
    return PointAnnotation(id: '${points.length}', geometry: options.geometry);
  }
}

class RecordingLines extends Fake implements PolylineAnnotationManager {
  final List<PolylineAnnotationOptions> lines = [];
  @override
  Future<void> deleteAll() async => lines.clear();
  @override
  Future<PolylineAnnotation> create(PolylineAnnotationOptions options) async {
    lines.add(options);
    return PolylineAnnotation(
      id: '${lines.length}',
      geometry: options.geometry,
    );
  }
}

class RecordingAnnotations extends Fake implements AnnotationManager {
  final points = RecordingPoints();
  final lines = RecordingLines();
  @override
  Future<PointAnnotationManager> createPointAnnotationManager({
    String? id,
    String? below,
  }) async => points;
  @override
  Future<PolylineAnnotationManager> createPolylineAnnotationManager({
    String? id,
    String? below,
  }) async => lines;
}

class RecordingMap extends Fake implements MapboxMap {
  @override
  final RecordingAnnotations annotations = RecordingAnnotations();
  List<Point> fitted = [];
  MbxEdgeInsets? padding;
  CameraOptions? camera;
  @override
  Future<CameraOptions> cameraForCoordinatesPadding(
    List<Point> coordinates,
    CameraOptions camera,
    MbxEdgeInsets? coordinatesPadding,
    double? maxZoom,
    ScreenCoordinate? offset,
  ) async {
    fitted = coordinates;
    padding = coordinatesPadding;
    return CameraOptions(zoom: 7);
  }

  @override
  Future<void> setCamera(CameraOptions cameraOptions) async {
    camera = cameraOptions;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'route renders both markers, full polyline, and fits every vertex',
    () async {
      final map = RecordingMap();
      final service = MapboxService()..setMapController(map);
      final origin = LocationInfo(
        latitude: 0,
        longitude: 0,
        timestamp: DateTime.now(),
      );
      const destination = RouteDestination(
        name: 'Destination',
        latitude: 1,
        longitude: 2,
      );
      final route = NavigationRoute(
        origin: origin,
        destination: destination,
        coordinates: [
          [0, 0],
          [5, 7],
          [2, 1],
        ],
        distanceMeters: 200,
        durationSeconds: 60,
      );
      await service.renderNavigation(
        origin: origin,
        destination: destination,
        route: route,
      );
      expect(map.annotations.points.points.map((p) => p.textField), [
        'Current location',
        'Destination',
      ]);
      expect(
        map.annotations.points.points.every((p) => p.image!.isNotEmpty),
        isTrue,
      );
      expect(map.annotations.lines.lines.single.geometry.coordinates.length, 3);
      expect(map.fitted.map((p) => p.coordinates.toJson()), [
        [0, 0],
        [0, 0],
        [5, 7],
        [2, 1],
        [2, 1],
      ]);
      expect(map.padding!.left, 48);
      expect(map.camera!.zoom, 7);
      // A new request removes the old route/destination rather than accumulating.
      await service.renderNavigation(origin: origin, fitCamera: false);
      expect(map.annotations.points.points.length, 1);
      expect(map.annotations.lines.lines, isEmpty);
      service.dispose();
      expect(service.isInitialized, isFalse);
    },
  );

  test('camera and navigation maps cannot overwrite each other', () async {
    final cameraMap = RecordingMap();
    final navigationMap = RecordingMap();
    final camera = MapboxService()..setMapController(cameraMap);
    final navigation = MapboxService()..setMapController(navigationMap);
    navigation.dispose();
    expect(camera.mapController, same(cameraMap));
    expect(camera.isInitialized, isTrue);
  });
}
