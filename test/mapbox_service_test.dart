import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';
import 'package:geotag_camera/services/mapbox_service.dart';

class RecordingMap extends Fake implements MapboxMap {
  final recordingAnnotations = RecordingAnnotations();
  @override
  AnnotationManager get annotations => recordingAnnotations;

  List<Point>? fittedPoints;
  CameraOptions? appliedCamera;
  MbxEdgeInsets? padding;
  double? maximumZoom;
  @override
  Future<CameraOptions> cameraForCoordinatesPadding(
    List<Point> coordinates,
    CameraOptions camera,
    MbxEdgeInsets? coordinatesPadding,
    double? maxZoom,
    ScreenCoordinate? offset,
  ) async {
    fittedPoints = coordinates;
    padding = coordinatesPadding;
    maximumZoom = maxZoom;
    return CameraOptions(zoom: 6);
  }

  @override
  Future<Size> getSize() async => Size(width: 320, height: 80);

  @override
  Future<void> setCamera(CameraOptions cameraOptions) async {
    appliedCamera = cameraOptions;
  }
}

class RecordingAnnotations extends Fake implements AnnotationManager {
  final lines = RecordingLines();
  final circles = RecordingCircles();
  final creationOrder = <String>[];
  @override
  Future<PolylineAnnotationManager> createPolylineAnnotationManager({
    String? id,
    String? below,
  }) async {
    creationOrder.add('line');
    return lines;
  }

  @override
  Future<CircleAnnotationManager> createCircleAnnotationManager({
    String? id,
    String? below,
  }) async {
    creationOrder.add('circle');
    return circles;
  }
}

class RecordingLines extends Fake implements PolylineAnnotationManager {
  final drawn = <PolylineAnnotationOptions>[];
  @override
  Future<void> deleteAll() async => drawn.clear();
  @override
  Future<PolylineAnnotation> create(PolylineAnnotationOptions options) async {
    drawn.add(options);
    return FakeLine();
  }
}

class FakeLine extends Fake implements PolylineAnnotation {}

class RecordingCircles extends Fake implements CircleAnnotationManager {
  final drawn = <CircleAnnotationOptions>[];
  @override
  Future<void> deleteAll() async => drawn.clear();
  @override
  Future<CircleAnnotation> create(CircleAnnotationOptions options) async {
    drawn.add(options);
    return FakeCircle();
  }
}

class FakeCircle extends Fake implements CircleAnnotation {}

void main() {
  test(
    'draws the road polyline below distinct endpoints and replaces stale overlays',
    () async {
      final native = RecordingMap();
      final map = MapboxService()..setMapController(native);
      await map.initializeNavigationAnnotations();
      await map.showNavigation(
        origin: const RouteCoordinate(21, 72),
        destination: const NavigationDestination(
          name: 'End',
          coordinate: RouteCoordinate(22, 73),
        ),
        route: NavigationRoute(
          coordinates: const [
            RouteCoordinate(21, 72),
            RouteCoordinate(24, 71),
            RouteCoordinate(22, 73),
          ],
          distanceMeters: 1000,
          durationSeconds: 600,
        ),
      );
      final annotations = native.recordingAnnotations;
      expect(annotations.creationOrder, ['line', 'circle']);
      expect(annotations.lines.drawn.single.geometry.coordinates.length, 3);
      expect(annotations.circles.drawn.map((p) => p.circleColor), [
        0xFF1976D2,
        0xFFE65100,
      ]);
      expect(annotations.circles.drawn.last.geometry.coordinates.lng, 73);
      await map.showNavigation(origin: const RouteCoordinate(21, 72));
      expect(annotations.lines.drawn, isEmpty);
      expect(annotations.circles.drawn.length, 1);
    },
  );

  test('fits full route geometry including detours and endpoints', () async {
    final native = RecordingMap();
    final map = MapboxService()..setMapController(native);
    await map.fitNavigation(
      origin: const RouteCoordinate(21, 72),
      destination: const NavigationDestination(
        name: 'End',
        coordinate: RouteCoordinate(22, 73),
      ),
      route: NavigationRoute(
        coordinates: const [
          RouteCoordinate(21, 72),
          RouteCoordinate(25, 70),
          RouteCoordinate(22, 73),
        ],
        distanceMeters: 100,
        durationSeconds: 10,
      ),
    );
    expect(native.fittedPoints!.length, 5);
    expect(native.fittedPoints!.map((p) => p.coordinates.lng), contains(70));
    expect(native.padding!.top, greaterThan(0));
    expect(native.padding!.top, lessThan(40));
    expect(native.maximumZoom, 15);
    expect(native.appliedCamera!.zoom, 6);
  });
  test(
    'lets SDK fit antimeridian and coincident endpoints with a zoom cap',
    () async {
      for (final longitudes in [
        [179.9, -179.9],
        [72.0, 72.0],
      ]) {
        final native = RecordingMap();
        final map = MapboxService()..setMapController(native);
        await map.fitNavigation(
          origin: RouteCoordinate(21, longitudes.first),
          destination: NavigationDestination(
            name: 'End',
            coordinate: RouteCoordinate(21, longitudes.last),
          ),
        );
        expect(native.fittedPoints!.map((p) => p.coordinates.lng), longitudes);
        expect(native.maximumZoom, 15);
      }
    },
  );
  test(
    'camera preview and navigation maintain independent controllers',
    () async {
      final first = RecordingMap();
      final second = RecordingMap();
      final preview = MapboxService()..setMapController(first);
      final navigation = MapboxService()..setMapController(second);
      navigation.dispose();
      await preview.fitNavigation(origin: const RouteCoordinate(21, 72));
      expect(first.appliedCamera!.center!.coordinates.lat, 21);
      expect(second.appliedCamera, isNull);
      expect(preview.isInitialized, isTrue);
    },
  );
}
