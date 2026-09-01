import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';
import 'package:geotag_camera/services/mapbox_service.dart';

class RecordingMap extends Fake implements MapboxMap {
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

void main() {
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
