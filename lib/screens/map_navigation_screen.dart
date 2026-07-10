import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../models/navigation_models.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';

enum NavigationLoadState { locating, idle, routing, routeReady, error }

class MapNavigationController extends GetxController {
  MapNavigationController(this._navigationService);

  final NavigationService _navigationService;
  final TextEditingController destinationController = TextEditingController();

  final Rx<NavigationLoadState> state = NavigationLoadState.locating.obs;
  final Rxn<NavigationCoordinate> currentLocation = Rxn<NavigationCoordinate>();
  final Rxn<NavigationRoute> route = Rxn<NavigationRoute>();
  final Rxn<NavigationFailureType> failureType = Rxn<NavigationFailureType>();
  final RxString errorMessage = ''.obs;

  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;

  bool get isBusy =>
      state.value == NavigationLoadState.locating ||
      state.value == NavigationLoadState.routing;

  @override
  void onInit() {
    super.onInit();
    locateUser();
  }

  @override
  void onClose() {
    destinationController.dispose();
    _navigationService.dispose();
    super.onClose();
  }

  Future<void> locateUser() async {
    state.value = NavigationLoadState.locating;
    _clearError();

    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );
    if (!result.success || result.info == null) {
      _showLocationFailure(result);
      return;
    }

    currentLocation.value = NavigationCoordinate(
      latitude: result.info!.latitude,
      longitude: result.info!.longitude,
    );
    state.value = route.value == null
        ? NavigationLoadState.idle
        : NavigationLoadState.routeReady;
    await _renderMapContent();
  }

  Future<void> findRoute() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _clearError();

    var origin = currentLocation.value;
    if (origin == null) {
      await locateUser();
      origin = currentLocation.value;
      if (origin == null) {
        return;
      }
    }

    state.value = NavigationLoadState.routing;
    route.value = null;
    await _renderMapContent();
    try {
      final result = await _navigationService.findRoute(
        origin: origin,
        destinationInput: destinationController.text,
      );
      route.value = result;
      state.value = NavigationLoadState.routeReady;
      await _renderMapContent();
    } on NavigationException catch (error) {
      _showFailure(error.type, error.message);
    } catch (_) {
      _showFailure(
        NavigationFailureType.unknown,
        'Something went wrong while creating the route. Please try again.',
      );
    }
  }

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    try {
      _mapboxMap = mapboxMap;
      _pointAnnotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();
      _polylineAnnotationManager = await mapboxMap.annotations
          .createPolylineAnnotationManager();
      await _renderMapContent();
    } catch (_) {
      _showFailure(
        NavigationFailureType.mapLoad,
        'The map could not be prepared. Check your connection and try again.',
      );
    }
  }

  void onMapLoadError(String _) {
    if (failureType.value == NavigationFailureType.mapConfiguration) {
      return;
    }
    _showFailure(
      NavigationFailureType.mapLoad,
      'The map could not be loaded. Check your connection and try again.',
    );
  }

  Future<void> openRelevantSettings() async {
    if (failureType.value ==
        NavigationFailureType.permissionPermanentlyDenied) {
      await geo.Geolocator.openAppSettings();
      return;
    }
    if (failureType.value == NavigationFailureType.locationServiceDisabled) {
      await geo.Geolocator.openLocationSettings();
    }
  }

  void _showLocationFailure(LocationResult result) {
    switch (result.error) {
      case LocationError.serviceDisabled:
        _showFailure(
          NavigationFailureType.locationServiceDisabled,
          result.errorMessage ?? 'Turn on Location Services to continue.',
        );
        return;
      case LocationError.permissionDenied:
        _showFailure(
          NavigationFailureType.permissionDenied,
          result.errorMessage ?? 'Location permission is required to navigate.',
        );
        return;
      case LocationError.permissionPermanentlyDenied:
        _showFailure(
          NavigationFailureType.permissionPermanentlyDenied,
          result.errorMessage ??
              'Allow location access in Settings to use navigation.',
        );
        return;
      case LocationError.timeout:
        _showFailure(
          NavigationFailureType.locationUnavailable,
          result.errorMessage ??
              'Your location could not be determined. Move outdoors and retry.',
        );
        return;
      case LocationError.unknown:
      case null:
        _showFailure(
          NavigationFailureType.locationUnavailable,
          result.errorMessage ??
              'Your location is unavailable right now. Please retry.',
        );
        return;
    }
  }

  void _showFailure(NavigationFailureType type, String message) {
    failureType.value = type;
    errorMessage.value = message;
    state.value = NavigationLoadState.error;
  }

  void _clearError() {
    failureType.value = null;
    errorMessage.value = '';
  }

  Future<void> _renderMapContent() async {
    final map = _mapboxMap;
    final points = _pointAnnotationManager;
    final lines = _polylineAnnotationManager;
    final origin = currentLocation.value;
    if (map == null || points == null || lines == null || origin == null) {
      return;
    }

    await points.deleteAll();
    await lines.deleteAll();

    final currentIcon = await _createMarkerIcon(const Color(0xFF1565C0));
    await points.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(origin.longitude, origin.latitude),
        ),
        image: currentIcon,
        iconSize: 0.8,
        iconOffset: <double?>[0, -8],
        textField: 'Current location',
        textOffset: <double?>[0, 1.4],
        textSize: 12,
        textColor: 0xFF0D1B2A,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.5,
      ),
    );

    final currentRoute = route.value;
    if (currentRoute == null) {
      await map.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(origin.longitude, origin.latitude),
          ),
          zoom: MapboxConfig.defaultZoom,
        ),
        MapAnimationOptions(duration: 700),
      );
      return;
    }

    final destination = currentRoute.destination.coordinate;
    final destinationIcon = await _createMarkerIcon(const Color(0xFFD32F2F));
    await points.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(destination.longitude, destination.latitude),
        ),
        image: destinationIcon,
        iconSize: 0.8,
        iconOffset: <double?>[0, -8],
        textField: 'Destination',
        textOffset: <double?>[0, 1.4],
        textSize: 12,
        textColor: 0xFF0D1B2A,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.5,
      ),
    );

    final routePositions = currentRoute.coordinates
        .map(
          (coordinate) => Position(coordinate.longitude, coordinate.latitude),
        )
        .toList(growable: false);
    await lines.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: routePositions),
        lineColor: 0xFF1565C0,
        lineBorderColor: 0xFFFFFFFF,
        lineBorderWidth: 1.5,
        lineWidth: 6,
        lineOpacity: 0.95,
      ),
    );

    final camera = await map.cameraForCoordinatesPadding(
      currentRoute.coordinates
          .map(
            (coordinate) => Point(
              coordinates: Position(coordinate.longitude, coordinate.latitude),
            ),
          )
          .toList(growable: false),
      CameraOptions(bearing: 0, pitch: 0),
      MbxEdgeInsets(top: 150, left: 48, bottom: 260, right: 48),
      16,
      null,
    );
    await map.easeTo(camera, MapAnimationOptions(duration: 900));
  }

  Future<Uint8List> _createMarkerIcon(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = ui.Size(48, 58);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final path = Path()
      ..moveTo(24, 56)
      ..cubicTo(20, 47, 9, 36, 9, 24)
      ..arcToPoint(
        const Offset(39, 24),
        radius: const Radius.circular(15),
        clockwise: true,
      )
      ..cubicTo(39, 36, 28, 47, 24, 56)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);
    canvas.drawCircle(const Offset(24, 24), 5, border);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not render map marker.');
    }
    return byteData.buffer.asUint8List();
  }
}

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text('Map Navigation'),
        backgroundColor: const Color(0xFF101820),
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildMap()),
          Positioned(top: 12, left: 12, right: 12, child: _buildSearchCard()),
          Positioned(
            left: 12,
            right: 12,
            top: 100,
            child: Obx(() => _buildStatusCard()),
          ),
          Positioned(
            right: 16,
            bottom: 176,
            child: Obx(
              () => FloatingActionButton.small(
                heroTag: 'current-location',
                onPressed: controller.isBusy ? null : controller.locateUser,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1565C0),
                child: controller.state.value == NavigationLoadState.locating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Obx(() => _buildRouteSummary()),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (!MapboxConfig.isConfigured) {
      return const ColoredBox(
        color: Color(0xFFE8EEF2),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Mapbox is not configured. Add MAPBOX_ACCESS_TOKEN at build time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF263238), fontSize: 16),
            ),
          ),
        ),
      );
    }

    return MapWidget(
      key: const ValueKey('navigation-map'),
      styleUri: MapboxConfig.streetStyle,
      viewport: CameraViewportState(
        center: Point(coordinates: Position(0, 20)),
        zoom: 1.5,
      ),
      onMapCreated: controller.onMapCreated,
      onMapLoadErrorListener: (event) =>
          controller.onMapLoadError(event.message),
    );
  }

  Widget _buildSearchCard() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: <Widget>[
            const Icon(Icons.place_outlined, color: Color(0xFFD32F2F)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('destination-input'),
                controller: controller.destinationController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => controller.findRoute(),
                style: const TextStyle(color: Color(0xFF17202A)),
                decoration: const InputDecoration(
                  hintText: 'Enter destination',
                  hintStyle: TextStyle(color: Color(0xFF6B7785)),
                  border: InputBorder.none,
                ),
              ),
            ),
            Obx(
              () => IconButton.filled(
                key: const ValueKey('find-route-button'),
                tooltip: 'Find route',
                onPressed: controller.isBusy ? null : controller.findRoute,
                icon: controller.state.value == NavigationLoadState.routing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.directions),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    if (controller.state.value == NavigationLoadState.locating) {
      return _messageCard(
        icon: Icons.gps_fixed,
        message: 'Detecting your current location…',
        showProgress: true,
      );
    }
    if (controller.state.value != NavigationLoadState.error) {
      return const SizedBox.shrink();
    }

    final type = controller.failureType.value;
    final canOpenSettings =
        type == NavigationFailureType.permissionPermanentlyDenied ||
        type == NavigationFailureType.locationServiceDisabled;
    return _messageCard(
      icon: _failureIcon(type),
      message: controller.errorMessage.value,
      actions: <Widget>[
        if (canOpenSettings)
          TextButton(
            onPressed: controller.openRelevantSettings,
            child: const Text('Open settings'),
          ),
        TextButton(
          onPressed: _isLocationFailure(type)
              ? controller.locateUser
              : controller.findRoute,
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildRouteSummary() {
    final route = controller.route.value;
    if (route == null) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: 8,
      color: const Color(0xFF101820),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              route.destination.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _summaryValue(
                  Icons.route,
                  route.formattedDistance,
                  'Total distance',
                ),
                const SizedBox(width: 28),
                _summaryValue(
                  Icons.schedule,
                  route.formattedDuration,
                  'Estimated time',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryValue(IconData icon, String value, String label) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Icon(icon, color: const Color(0xFF64B5F6)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(label, style: const TextStyle(color: Color(0xFFB0BEC5))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    return Material(
      elevation: 4,
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            if (showProgress)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(icon, color: const Color(0xFFD32F2F)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFF263238)),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  IconData _failureIcon(NavigationFailureType? type) {
    if (type == NavigationFailureType.network ||
        type == NavigationFailureType.mapLoad) {
      return Icons.wifi_off;
    }
    if (type == NavigationFailureType.invalidDestination ||
        type == NavigationFailureType.noRoute) {
      return Icons.wrong_location_outlined;
    }
    return Icons.location_disabled;
  }

  bool _isLocationFailure(NavigationFailureType? type) {
    return type == NavigationFailureType.permissionDenied ||
        type == NavigationFailureType.permissionPermanentlyDenied ||
        type == NavigationFailureType.locationServiceDisabled ||
        type == NavigationFailureType.locationUnavailable;
  }
}
