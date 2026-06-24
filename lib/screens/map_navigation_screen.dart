import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../models/navigation_models.dart';
import '../services/location_service.dart';
import '../services/map_navigation_service.dart';

enum _LocationRecoveryAction {
  none,
  appSettings,
  locationSettings,
}

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildMap(),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildSearchBar(),
            ),
            Positioned(
              right: 16,
              bottom: 178,
              child: _buildCurrentLocationButton(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildRouteSheet(),
            ),
            Obx(
              () => controller.isLoading.value
                  ? Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black.withOpacity(0.08),
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return Obx(() {
      if (!controller.canRenderMap.value) {
        return Container(
          color: Colors.grey.shade900,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                controller.errorMessage.value.isEmpty
                    ? 'Map unavailable'
                    : controller.errorMessage.value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }

      return MapWidget(
        key: const ValueKey('map_navigation_map'),
        styleUri: MapboxConfig.streetStyle,
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(72.8366927, 21.2318378)),
          zoom: 12,
        ),
        onMapCreated: controller.onMapCreated,
      );
    });
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: Get.back,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back',
          ),
          Expanded(
            child: TextField(
              controller: controller.destinationController,
              enabled: !controller.isLoading.value,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => controller.buildRoute(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Destination',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Obx(
            () => IconButton(
              onPressed:
                  controller.isLoading.value ? null : controller.buildRoute,
              icon: controller.isLoading.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.search, color: Colors.white),
              tooltip: 'Search',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationButton() {
    return Obx(
      () => Material(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(16),
        child: IconButton(
          onPressed: controller.isLoading.value
              ? null
              : controller.refreshCurrentLocation,
          icon: const Icon(Icons.my_location, color: Colors.white),
          tooltip: 'Current location',
        ),
      ),
    );
  }

  Widget _buildRouteSheet() {
    return Obx(() {
      final route = controller.activeRoute.value;
      final hasError = controller.errorMessage.value.isNotEmpty;

      return Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasError ? Colors.red.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasError ? Icons.error_outline : Icons.route,
                    color:
                        hasError ? Colors.red.shade700 : Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    route == null
                        ? controller.statusMessage.value
                        : 'Route ready',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 12),
              Text(
                controller.errorMessage.value,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              if (controller.hasRecoveryAction.value) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.openRecoverySettings,
                  icon: const Icon(Icons.settings),
                  label: Text(controller.recoveryActionLabel.value),
                ),
              ],
            ],
            if (route != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildMetric(
                    Icons.social_distance,
                    'Distance',
                    route.formattedDistance,
                  ),
                  const SizedBox(width: 12),
                  _buildMetric(
                    Icons.schedule,
                    'Time',
                    route.formattedDuration,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildAddressLine(
                Colors.blue.shade700,
                'From',
                route.origin.label,
              ),
              const SizedBox(height: 8),
              _buildAddressLine(
                Colors.red.shade700,
                'To',
                route.destination.label,
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildMetric(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue.shade700, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressLine(Color color, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class MapNavigationController extends GetxController {
  final TextEditingController destinationController = TextEditingController();

  final RxBool canRenderMap = false.obs;
  final RxBool isLoading = false.obs;
  final RxString statusMessage = 'Ready'.obs;
  final RxString errorMessage = ''.obs;
  final RxString recoveryActionLabel = ''.obs;
  final RxBool hasRecoveryAction = false.obs;
  final Rxn<NavigationCoordinate> currentLocation = Rxn<NavigationCoordinate>();
  final Rxn<NavigationCoordinate> destination = Rxn<NavigationCoordinate>();
  final Rxn<NavigationRoute> activeRoute = Rxn<NavigationRoute>();

  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  Uint8List? _originMarkerImage;
  Uint8List? _destinationMarkerImage;
  _LocationRecoveryAction _recoveryAction = _LocationRecoveryAction.none;

  @override
  void onInit() {
    super.onInit();
    if (MapNavigationService.hasConfiguredAccessToken) {
      MapboxOptions.setAccessToken(MapboxConfig.accessToken);
      canRenderMap.value = true;
    } else {
      errorMessage.value =
          'Mapbox access token is missing. Add it before using navigation.';
      statusMessage.value = 'Map unavailable';
    }
  }

  @override
  void onClose() {
    destinationController.dispose();
    super.onClose();
  }

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      _pointAnnotationManager =
          await mapboxMap.annotations.createPointAnnotationManager();
      _polylineAnnotationManager =
          await mapboxMap.annotations.createPolylineAnnotationManager();
      await _pointAnnotationManager?.setIconAllowOverlap(true);
      await _pointAnnotationManager?.setTextAllowOverlap(true);
      await _pointAnnotationManager?.setTextIgnorePlacement(true);
      _originMarkerImage = await _createMarkerImage(Colors.blue.shade700);
      _destinationMarkerImage = await _createMarkerImage(Colors.red.shade700);
      await _renderRoute();
    } catch (error) {
      _setError(
        'The map could not prepare navigation overlays. Please reopen the map.',
      );
      debugPrint('Map navigation setup failed: $error');
    }
  }

  Future<void> buildRoute() async {
    if (isLoading.value) return;

    _clearError();
    final destinationText = destinationController.text.trim();
    if (destinationText.isEmpty) {
      _setError('Enter a destination to build a route.');
      return;
    }

    isLoading.value = true;
    try {
      statusMessage.value = 'Getting current location';
      final origin = await _resolveCurrentLocation();
      currentLocation.value = origin;

      statusMessage.value = 'Finding destination';
      final resolvedDestination =
          await MapNavigationService.geocodeDestination(destinationText);
      destination.value = resolvedDestination;

      statusMessage.value = 'Generating route';
      final route = await MapNavigationService.fetchRoute(
        origin: origin,
        destination: resolvedDestination,
      );
      activeRoute.value = route;
      statusMessage.value = 'Route ready';
      await _renderRoute();
    } on NavigationException catch (error) {
      activeRoute.value = null;
      _setError(error.message);
    } catch (error) {
      activeRoute.value = null;
      _setError('Something went wrong while building the route.');
      debugPrint('Navigation route error: $error');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshCurrentLocation() async {
    if (isLoading.value) return;

    _clearError();
    isLoading.value = true;
    try {
      statusMessage.value = 'Getting current location';
      final origin = await _resolveCurrentLocation();
      currentLocation.value = origin;
      destination.value = null;
      activeRoute.value = null;
      statusMessage.value = 'Current location ready';
      await _renderCurrentLocation(origin);
    } on NavigationException catch (error) {
      _setError(error.message);
    } catch (error) {
      _setError('Unable to refresh current location.');
      debugPrint('Refresh location error: $error');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> openRecoverySettings() async {
    switch (_recoveryAction) {
      case _LocationRecoveryAction.appSettings:
        await Geolocator.openAppSettings();
        break;
      case _LocationRecoveryAction.locationSettings:
        await Geolocator.openLocationSettings();
        break;
      case _LocationRecoveryAction.none:
        break;
    }
  }

  Future<NavigationCoordinate> _resolveCurrentLocation() async {
    _recoveryAction = _LocationRecoveryAction.none;
    hasRecoveryAction.value = false;
    recoveryActionLabel.value = '';

    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );
    if (!result.success || result.info == null) {
      switch (result.error) {
        case LocationError.serviceDisabled:
          _setRecoveryAction(
            _LocationRecoveryAction.locationSettings,
            'Open location settings',
          );
          break;
        case LocationError.permissionPermanentlyDenied:
          _setRecoveryAction(
            _LocationRecoveryAction.appSettings,
            'Open app settings',
          );
          break;
        case LocationError.permissionDenied:
        case LocationError.timeout:
        case LocationError.unknown:
        case null:
          break;
      }

      throw NavigationException(
        NavigationFailureType.location,
        result.errorMessage ?? 'Unable to get your current GPS location.',
      );
    }

    final info = result.info!;
    return NavigationCoordinate(
      latitude: info.latitude,
      longitude: info.longitude,
      label: info.address == null || info.address!.trim().isEmpty
          ? 'Current Location'
          : info.address!.trim(),
    );
  }

  Future<void> _renderCurrentLocation(NavigationCoordinate origin) async {
    if (_pointAnnotationManager == null) return;

    await _pointAnnotationManager?.deleteAll();
    await _polylineAnnotationManager?.deleteAll();
    await _pointAnnotationManager?.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(origin.longitude, origin.latitude),
        ),
        image: _originMarkerImage,
        textField: 'Current Location',
        textSize: 12,
        textColor: Colors.black.value,
        textHaloColor: Colors.white.value,
        textHaloWidth: 1.2,
        textOffset: <double?>[0, 1.4],
      ),
    );

    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(origin.longitude, origin.latitude)),
        zoom: MapboxConfig.defaultZoom,
      ),
      MapAnimationOptions(duration: 700, startDelay: 0),
    );
  }

  Future<void> _renderRoute() async {
    final route = activeRoute.value;
    if (route == null ||
        _pointAnnotationManager == null ||
        _polylineAnnotationManager == null) {
      return;
    }

    await _pointAnnotationManager?.deleteAll();
    await _polylineAnnotationManager?.deleteAll();

    await _polylineAnnotationManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: route.path
              .map((point) => Position(point.longitude, point.latitude))
              .toList(),
        ),
        lineColor: Colors.blue.shade600.value,
        lineBorderColor: Colors.white.value,
        lineBorderWidth: 1.2,
        lineOpacity: 0.92,
        lineWidth: 6,
      ),
    );

    await _pointAnnotationManager?.createMulti([
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(route.origin.longitude, route.origin.latitude),
        ),
        image: _originMarkerImage,
        textField: 'Current Location',
        textSize: 12,
        textColor: Colors.black.value,
        textHaloColor: Colors.white.value,
        textHaloWidth: 1.2,
        textOffset: <double?>[0, 1.4],
      ),
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            route.destination.longitude,
            route.destination.latitude,
          ),
        ),
        image: _destinationMarkerImage,
        textField: 'Destination',
        textSize: 12,
        textColor: Colors.black.value,
        textHaloColor: Colors.white.value,
        textHaloWidth: 1.2,
        textOffset: <double?>[0, 1.4],
      ),
    ]);

    await _fitCameraToRoute(route);
  }

  Future<void> _fitCameraToRoute(NavigationRoute route) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final points = <NavigationCoordinate>[
      route.origin,
      ...route.path,
      route.destination,
    ];

    double minLatitude = points.first.latitude;
    double maxLatitude = points.first.latitude;
    double minLongitude = points.first.longitude;
    double maxLongitude = points.first.longitude;

    for (final point in points) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }

    final padding = MbxEdgeInsets(
      top: 150,
      left: 44,
      bottom: 260,
      right: 44,
    );

    try {
      if (minLatitude == maxLatitude && minLongitude == maxLongitude) {
        await mapboxMap.flyTo(
          CameraOptions(
            center: Point(
              coordinates:
                  Position(route.origin.longitude, route.origin.latitude),
            ),
            zoom: MapboxConfig.defaultZoom,
            padding: padding,
          ),
          MapAnimationOptions(duration: 700, startDelay: 0),
        );
        return;
      }

      final camera = await mapboxMap.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLongitude, minLatitude)),
          northeast: Point(coordinates: Position(maxLongitude, maxLatitude)),
          infiniteBounds: false,
        ),
        padding,
        null,
        null,
        MapboxConfig.maxZoom,
        null,
      );

      await mapboxMap.flyTo(
        camera,
        MapAnimationOptions(duration: 900, startDelay: 0),
      );
    } catch (error) {
      debugPrint('Failed to fit route camera: $error');
    }
  }

  Future<Uint8List> _createMarkerImage(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = ui.Size(72, 72);
    const center = Offset(36, 28);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center.translate(0, 3), 19, shadowPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 18, fillPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, 18, borderPaint);

    final pointPath = Path()
      ..moveTo(center.dx - 7, center.dy + 13)
      ..lineTo(center.dx + 7, center.dy + 13)
      ..lineTo(center.dx, center.dy + 30)
      ..close();
    canvas.drawPath(pointPath, fillPaint);
    canvas.drawPath(pointPath, borderPaint);

    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, innerPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _setError(String message) {
    errorMessage.value = message;
    statusMessage.value = 'Needs attention';
    HapticFeedback.lightImpact();
    Get.snackbar(
      'Navigation',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.black.withOpacity(0.85),
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    );
  }

  void _clearError() {
    errorMessage.value = '';
    _recoveryAction = _LocationRecoveryAction.none;
    hasRecoveryAction.value = false;
    recoveryActionLabel.value = '';
  }

  void _setRecoveryAction(
    _LocationRecoveryAction action,
    String label,
  ) {
    _recoveryAction = action;
    recoveryActionLabel.value = label;
    hasRecoveryAction.value = true;
  }
}
