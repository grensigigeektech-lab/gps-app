import 'package:flutter/material.dart' hide NavigationDestination;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/mapbox_config.dart';
import 'mapbox_directions_service.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MapboxService {
  MapboxMap? _mapController;
  PointAnnotationManager? _pointAnnotationManager;
  final List<PointAnnotation> _markers = [];
  PolylineAnnotationManager? _routeManager;
  CircleAnnotationManager? _endpointManager;

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
    if (!identical(_mapController, controller)) dispose();
    _mapController = controller;
  }

  Future<void> initializeAnnotationManager() async {
    final map = _mapController;
    if (map != null && _pointAnnotationManager == null) {
      final manager = await map.annotations.createPointAnnotationManager();
      if (identical(map, _mapController)) _pointAnnotationManager = manager;
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
  }) async {
    if (_pointAnnotationManager == null) {
      await initializeAnnotationManager();
    }

    if (_pointAnnotationManager == null) return null;

    try {
      // Create marker icon
      final markerIconData = await _createMarkerIcon();

      final pointAnnotationOptions = PointAnnotationOptions(
        geometry: Point(coordinates: Position(longitude, latitude)),
        image: markerIconData,
        textField: title ?? '',
        textOffset: [0, 2],
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
        debugPrint('Failed to fetch static map: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Could not fetch static map.');
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

  static Future<Uint8List> _createMarkerIcon() async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final size = ui.Size(40.0, 40.0);

    // Draw red circle background
    final paint = Paint()
      ..color = Colors.red
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

    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  Future<void> initializeNavigationAnnotations() async {
    final map = _mapController;
    if (map == null) throw StateError('Map is not ready');
    // Line is created first so the endpoints render above it.
    final lines =
        _routeManager ??
        await map.annotations.createPolylineAnnotationManager();
    if (!identical(map, _mapController)) return;
    _routeManager = lines;
    final points =
        _endpointManager ??
        await map.annotations.createCircleAnnotationManager();
    if (identical(map, _mapController)) _endpointManager = points;
  }

  /// Replaces the complete navigation overlay; never leaves a stale route behind.
  Future<void> showNavigation({
    RouteCoordinate? origin,
    NavigationDestination? destination,
    NavigationRoute? route,
  }) async {
    final lines = _routeManager;
    final points = _endpointManager;
    if (lines == null || points == null) throw StateError('Map is not ready');
    await lines.deleteAll();
    await points.deleteAll();
    if (route != null) {
      await lines.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: route.coordinates
                .map((p) => Position(p.longitude, p.latitude))
                .toList(),
          ),
          lineColor: 0xFF1976D2,
          lineWidth: 6,
          lineBorderColor: 0xFFFFFFFF,
          lineBorderWidth: 1,
          lineJoin: LineJoin.ROUND,
        ),
      );
    }
    if (origin != null) {
      await points.create(
        CircleAnnotationOptions(
          geometry: _point(origin),
          circleColor: 0xFF1976D2,
          circleRadius: 9,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ),
      );
    }
    if (destination != null) {
      await points.create(
        CircleAnnotationOptions(
          geometry: _point(destination.coordinate),
          circleColor: 0xFFE65100,
          circleRadius: 9,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ),
      );
    }
  }

  /// Fit every route vertex, not just its endpoints (a route may detour).
  /// The map occupies its own layout area, so controls never cover the route.
  Future<void> fitNavigation({
    required RouteCoordinate origin,
    NavigationDestination? destination,
    NavigationRoute? route,
  }) async {
    final map = _mapController;
    if (map == null) throw StateError('Map is not ready');
    final coordinates = [
      origin,
      ...?route?.coordinates,
      if (destination != null) destination.coordinate,
    ];
    if (coordinates.length == 1) {
      await map.setCamera(
        CameraOptions(center: _point(origin), zoom: MapboxConfig.defaultZoom),
      );
      return;
    }
    final viewport = await map.getSize();
    final verticalPadding = (viewport.height * .15).clamp(0.0, 48.0);
    final horizontalPadding = (viewport.width * .12).clamp(0.0, 40.0);
    final camera = await map.cameraForCoordinatesPadding(
      coordinates.map(_point).toList(),
      CameraOptions(bearing: 0, pitch: 0),
      MbxEdgeInsets(
        top: verticalPadding,
        left: horizontalPadding,
        bottom: verticalPadding,
        right: horizontalPadding,
      ),
      MapboxConfig.defaultZoom,
      null,
    );
    await map.setCamera(camera);
  }

  static Point _point(RouteCoordinate coordinate) =>
      Point(coordinates: Position(coordinate.longitude, coordinate.latitude));

  void dispose() {
    _mapController = null;
    _pointAnnotationManager = null;
    _routeManager = null;
    _endpointManager = null;
    _markers.clear();
  }

  MapboxMap? get mapController => _mapController;
  bool get isInitialized => _mapController != null;
}
