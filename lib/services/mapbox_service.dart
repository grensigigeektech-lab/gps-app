import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/mapbox_config.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MapboxService {
  static MapboxMap? _mapController;
  static PointAnnotationManager? _pointAnnotationManager;
  static final List<PointAnnotation> _markers = [];

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

  static void setMapController(MapboxMap controller) {
    _mapController = controller;
  }

  static Future<void> initializeAnnotationManager() async {
    if (_mapController != null) {
      _pointAnnotationManager = await _mapController!.annotations
          .createPointAnnotationManager();
    }
  }

  static Future<void> updateUserLocation(
    double latitude,
    double longitude,
  ) async {
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
      await addMarker(latitude, longitude, title: 'Current Location');
    } catch (e) {
      debugPrint('Failed to update user location: $e');
    }
  }

  static Future<PointAnnotation?> addMarker(
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

  static Future<void> removeMarker(PointAnnotation marker) async {
    if (_pointAnnotationManager == null) return;

    try {
      await _pointAnnotationManager!.delete(marker);
      _markers.remove(marker);
    } catch (e) {
      debugPrint('Failed to remove marker: $e');
    }
  }

  static Future<void> clearAllMarkers() async {
    if (_pointAnnotationManager == null) return;

    try {
      await _pointAnnotationManager!.deleteAll();
      _markers.clear();
    } catch (e) {
      debugPrint('Failed to clear markers: $e');
    }
  }

  static Future<void> animateToLocation(
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
      debugPrint('Error fetching static map: $e');
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

    return byteData!.buffer.asUint8List();
  }

  static void dispose() {
    _mapController = null;
    _pointAnnotationManager = null;
    _markers.clear();
  }

  static MapboxMap? get mapController => _mapController;
  static bool get isInitialized => _mapController != null;
}
