import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/mapbox_config.dart';
import 'location_service.dart';
import 'navigation_service.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MapboxService {
  MapboxMap? _mapController;
  PointAnnotationManager? _pointAnnotationManager;
  final List<PointAnnotation> _markers = [];
  PolylineAnnotationManager? _polylineAnnotationManager;
  int _renderGeneration = 0;

  static Future<void> initialize(String accessToken) async {
    try {
      // Set access token for Mapbox
      MapboxOptions.setAccessToken(accessToken);
      debugPrint('Mapbox initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize Mapbox: $e');
      rethrow;
    }
  }

  void setMapController(MapboxMap controller) {
    _mapController = controller;
  }

  Future<void> initializeAnnotationManager() async {
    if (_mapController != null) {
      _pointAnnotationManager = await _mapController!.annotations
          .createPointAnnotationManager();
    }
  }

  Future<void> updateUserLocation(double latitude, double longitude) async {
    if (_mapController == null) return;

    try {
      final cameraOptions = CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: MapboxConfig.defaultZoom,
        padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        bearing: 0.0,
        pitch: 0.0,
      );

      await _mapController!.setCamera(cameraOptions);

      // Add or update user location marker
      await clearAllMarkers();
      await addMarker(latitude, longitude, title: 'Current Location');
    } catch (e) {
      debugPrint('Failed to update user location: $e');
    }
  }

  Future<PointAnnotation?> addMarker(
    double latitude,
    double longitude, {
    String? title,
    Color color = Colors.blue,
  }) async {
    if (_pointAnnotationManager == null) {
      await initializeAnnotationManager();
    }

    if (_pointAnnotationManager == null) return null;

    try {
      // Create marker icon
      final markerIconData = await _createMarkerIcon(color);

      final pointAnnotationOptions = PointAnnotationOptions(
        image: markerIconData,
        geometry: Point(coordinates: Position(longitude, latitude)),
        textField: title ?? '',
        textOpacity: 1.0,
        textSize: 12.0,
        textColor: 0xFF000000,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.0,
      );

      final created = await _pointAnnotationManager!.create(
        pointAnnotationOptions,
      );
      _markers.add(created);

      return created;
    } catch (e) {
      debugPrint('Failed to add marker: $e');
      return null;
    }
  }

  Future<void> removeMarker(PointAnnotation marker) async {
    if (_pointAnnotationManager == null) return;

    try {
      await _pointAnnotationManager!.delete(marker);
      _markers.remove(marker);
    } catch (e) {
      debugPrint('Failed to remove marker: $e');
    }
  }

  Future<void> clearAllMarkers() async {
    if (_pointAnnotationManager == null) return;

    try {
      await _pointAnnotationManager!.deleteAll();
      _markers.clear();
    } catch (e) {
      debugPrint('Failed to clear markers: $e');
    }
  }

  Future<void> animateToLocation(
    double latitude,
    double longitude, {
    double? zoom,
  }) async {
    if (_mapController == null) return;

    try {
      final cameraOptions = CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: zoom ?? MapboxConfig.defaultZoom,
        padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        bearing: 0.0,
        pitch: 0.0,
      );

      await _mapController!.setCamera(cameraOptions);
    } catch (e) {
      debugPrint('Failed to animate to location: $e');
    }
  }

  static String getStaticMapUrl(
    double latitude,
    double longitude, {
    int width = 300,
    int height = 200,
    String style = 'streets',
  }) {
    final styleUrl = _getStyleUrl(style);
    return 'https://api.mapbox.com/styles/v1/$styleUrl/static/pin-l-marker+ff0000($longitude,$latitude)/$longitude,$latitude,15,0/${width}x$height@2x?access_token=${MapboxConfig.accessToken}';
  }

  static Future<Uint8List?> getStaticMapImage(
    double latitude,
    double longitude, {
    int width = 300,
    int height = 200,
    String style = 'streets',
  }) async {
    try {
      final url = getStaticMapUrl(
        latitude,
        longitude,
        width: width,
        height: height,
        style: style,
      );
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        debugPrint('Failed to fetch map: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching map: $e');
      return null;
    }
  }

  static String _getStyleUrl(String style) {
    switch (style) {
      case 'satellite':
        return 'mapbox/satellite-v9';
      case 'dark':
        return 'mapbox/dark-v11';
      case 'light':
        return 'mapbox/light-v11';
      case 'outdoors':
        return 'mapbox/outdoors-v12';
      default:
        return 'mapbox/streets-v12';
    }
  }

  Future<Uint8List> _createMarkerIcon(Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final size = ui.Size(40.0, 40.0);

    // Draw red circle background
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 15.0, paint);

    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      15.0,
      borderPaint,
    );

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    final bytes = byteData!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    return bytes;
  }

  /// Render the current request only. Each screen owns its service instance,
  /// so opening navigation cannot steal the camera thumbnail's controller.
  Future<void> renderNavigation({
    LocationInfo? origin,
    RouteDestination? destination,
    NavigationRoute? route,
    bool fitCamera = true,
  }) async {
    final map = _mapController;
    if (map == null) return;
    final generation = ++_renderGeneration;
    bool active() => generation == _renderGeneration && map == _mapController;
    _polylineAnnotationManager ??= await map.annotations
        .createPolylineAnnotationManager();
    _pointAnnotationManager ??= await map.annotations
        .createPointAnnotationManager();
    if (!active()) return;
    await _pointAnnotationManager!.deleteAll();
    if (!active()) return;
    _markers.clear();
    await _polylineAnnotationManager!.deleteAll();
    if (!active()) return;
    if (route != null) {
      await _polylineAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: route.coordinates
                .map((p) => Position(p[0], p[1]))
                .toList(),
          ),
          lineColor: 0xFF1565C0,
          lineWidth: 6,
          lineOpacity: 0.9,
        ),
      );
    }
    if (!active()) return;
    if (origin != null) {
      await _createNavigationMarker(
        origin.latitude,
        origin.longitude,
        'Current location',
        Colors.blue,
        active,
      );
    }
    if (!active()) return;
    if (destination != null) {
      await _createNavigationMarker(
        destination.latitude,
        destination.longitude,
        'Destination',
        Colors.red,
        active,
      );
    }
    if (!active() || !fitCamera) return;
    if (route != null) {
      final points = [
        Point(
          coordinates: Position(route.origin.longitude, route.origin.latitude),
        ),
        ...route.coordinates.map(
          (p) => Point(coordinates: Position(p[0], p[1])),
        ),
        Point(
          coordinates: Position(
            route.destination.longitude,
            route.destination.latitude,
          ),
        ),
      ];
      final camera = await map.cameraForCoordinatesPadding(
        points,
        CameraOptions(bearing: 0, pitch: 0),
        MbxEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
        16,
        null,
      );
      if (active()) await map.setCamera(camera);
    } else if (origin != null) {
      await map.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(origin.longitude, origin.latitude),
          ),
          zoom: MapboxConfig.defaultZoom,
        ),
      );
    }
  }

  Future<void> _createNavigationMarker(
    double latitude,
    double longitude,
    String title,
    Color color,
    bool Function() active,
  ) async {
    final icon = await _createMarkerIcon(color);
    if (!active()) return;
    await _pointAnnotationManager!.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(longitude, latitude)),
        image: icon,
        textField: title,
        textOffset: [0, 1.8],
        textSize: 12,
        textColor: 0xFF000000,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 2,
      ),
    );
  }

  void dispose() {
    _renderGeneration++;
    _mapController = null;
    _pointAnnotationManager = null;
    _polylineAnnotationManager = null;
    _markers.clear();
  }

  MapboxMap? get mapController => _mapController;
  bool get isInitialized => _mapController != null;
}
