import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';

import '../config/mapbox_config.dart';
import '../services/map_navigation_service.dart';

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: MapboxConfig.hasValidAccessToken
                  ? MapWidget(
                      key: const ValueKey('navigation_map'),
                      styleUri: MapboxConfig.streetStyle,
                      viewport: CameraViewportState(
                        center: Point(
                          coordinates: Position(
                            MapboxConfig.defaultLongitude,
                            MapboxConfig.defaultLatitude,
                          ),
                        ),
                        zoom: 12,
                      ),
                      onMapCreated: controller.onMapCreated,
                      onMapLoadedListener: controller.onMapLoaded,
                      onMapLoadErrorListener: controller.onMapLoadError,
                    )
                  : const ColoredBox(
                      color: Color(0xFF111827),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Mapbox is not configured. Add a public access '
                            'token with MAPBOX_ACCESS_TOKEN to load the map.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildSearchPanel(context),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Obx(() => _buildBottomPanel(context)),
            ),
            Obx(() {
              if (!controller.isShowingLoading) {
                return const SizedBox.shrink();
              }

              return Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.28),
                  child: Center(
                    child: Container(
                      width: 230,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            controller.visibleLoadingMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: Get.back,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  'Map Navigation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Obx(
                () => IconButton(
                  tooltip: 'Refresh GPS',
                  onPressed: controller.isBusy
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          controller.detectCurrentLocation(forceRefresh: true);
                        },
                  icon: Icon(
                    Icons.my_location,
                    color: controller.isBusy
                        ? Colors.grey.shade600
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.destinationController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => controller.buildRoute(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter destination',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Obx(
                () => SizedBox(
                  height: 52,
                  width: 52,
                  child: ElevatedButton(
                    onPressed: controller.isBusy
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            controller.buildRoute();
                          },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Icon(Icons.route),
                  ),
                ),
              ),
            ],
          ),
          Obx(() {
            if (controller.errorMessage.value.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade700.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.errorMessage.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (controller.canOpenSettings) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: controller.openRelevantSettings,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Open Settings'),
                    ),
                  ] else if (controller.canRetry) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: controller.retryLastAction,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    final route = controller.activeRoute.value;
    final current = controller.currentCoordinate.value;

    if (route != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              route.destinationName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: route.formattedDistance,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetric(
                    icon: Icons.schedule,
                    label: 'ETA',
                    value: route.formattedDuration,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.fitRouteCamera,
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('Fit route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: controller.clearRoute,
                    icon: const Icon(Icons.close),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            current == null ? Icons.location_searching : Icons.gps_fixed,
            color: current == null ? Colors.orangeAccent : Colors.greenAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              current == null
                  ? 'Waiting for current GPS location.'
                  : 'Current GPS location detected. Enter a destination to route.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MapNavigationController extends GetxController {
  final TextEditingController destinationController = TextEditingController();

  final RxBool isMapReady = false.obs;
  final RxBool isMapLoading = MapboxConfig.hasValidAccessToken.obs;
  final RxBool isLoadingLocation = false.obs;
  final RxBool isRouting = false.obs;
  final RxString loadingMessage = ''.obs;
  final RxString errorMessage = ''.obs;
  final Rxn<NavigationCoordinate> currentCoordinate =
      Rxn<NavigationCoordinate>();
  final Rxn<NavigationRoute> activeRoute = Rxn<NavigationRoute>();

  MapNavigationErrorType? _lastErrorType;
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _markerManager;
  PointAnnotationManager? _labelManager;
  PolylineAnnotationManager? _routeLineManager;

  bool get isBusy => isLoadingLocation.value || isRouting.value;
  bool get isShowingLoading => isBusy || isMapLoading.value;

  String get visibleLoadingMessage {
    if (loadingMessage.value.isNotEmpty) {
      return loadingMessage.value;
    }
    return 'Loading map...';
  }

  bool get canOpenSettings {
    return _lastErrorType == MapNavigationErrorType.serviceDisabled ||
        _lastErrorType == MapNavigationErrorType.permissionPermanentlyDenied;
  }

  bool get canRetry {
    return _lastErrorType == MapNavigationErrorType.permissionDenied ||
        _lastErrorType == MapNavigationErrorType.locationUnavailable ||
        _lastErrorType == MapNavigationErrorType.network ||
        _lastErrorType == MapNavigationErrorType.unknown;
  }

  @override
  void onInit() {
    super.onInit();
    if (!MapboxConfig.hasValidAccessToken) {
      _setError(
        const MapNavigationException(
          MapNavigationErrorType.mapboxConfiguration,
          'Mapbox is not configured. Add a public access token to use navigation.',
        ),
      );
      return;
    }
    detectCurrentLocation();
  }

  @override
  void onClose() {
    destinationController.dispose();
    super.onClose();
  }

  Future<void> detectCurrentLocation({bool forceRefresh = false}) async {
    if (isBusy) return;

    isLoadingLocation.value = true;
    loadingMessage.value = 'Finding current GPS location...';
    _clearError();

    try {
      currentCoordinate.value = await MapNavigationService.getCurrentCoordinate(
        forceRefresh: forceRefresh,
      );
      await _renderMapState();
      await _focusOnCurrentLocation();
    } on MapNavigationException catch (error) {
      _setError(error);
    } catch (error) {
      _setError(
        MapNavigationException(
          MapNavigationErrorType.unknown,
          'Could not get your current location. Try again.',
          cause: error,
        ),
      );
    } finally {
      isLoadingLocation.value = false;
      loadingMessage.value = '';
    }
  }

  Future<void> buildRoute() async {
    if (isBusy) return;

    isRouting.value = true;
    loadingMessage.value = 'Building route...';
    _clearError();

    try {
      final route = await MapNavigationService.createRouteToDestination(
        destinationController.text,
      );
      currentCoordinate.value = route.origin;
      activeRoute.value = route;
      await _renderMapState();
      await fitRouteCamera();
    } on MapNavigationException catch (error) {
      _setError(error);
    } catch (error) {
      _setError(
        MapNavigationException(
          MapNavigationErrorType.unknown,
          'Could not build navigation. Try again.',
          cause: error,
        ),
      );
    } finally {
      isRouting.value = false;
      loadingMessage.value = '';
    }
  }

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    try {
      _mapboxMap = mapboxMap;
      _routeLineManager = await mapboxMap.annotations
          .createPolylineAnnotationManager();
      _markerManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _labelManager = await mapboxMap.annotations
          .createPointAnnotationManager();
      isMapReady.value = true;
      await _renderMapState();

      if (activeRoute.value != null) {
        await fitRouteCamera();
      } else {
        await _focusOnCurrentLocation();
      }
    } catch (error) {
      isMapLoading.value = false;
      _setMapError(error);
    }
  }

  void onMapLoaded(MapLoadedEventData _) {
    isMapLoading.value = false;
    if (_lastErrorType == MapNavigationErrorType.mapUnavailable) {
      _clearError();
    }
  }

  void onMapLoadError(MapLoadingErrorEventData event) {
    isMapLoading.value = false;
    if (_lastErrorType == MapNavigationErrorType.mapUnavailable) {
      return;
    }
    _setMapError(event.message);
  }

  Future<void> fitRouteCamera() async {
    final mapboxMap = _mapboxMap;
    final route = activeRoute.value;

    if (mapboxMap == null || route == null || route.routePoints.isEmpty) {
      return;
    }

    try {
      final points = <Point>[
        _toPoint(route.origin),
        ...route.routePoints.map(_toPoint),
        _toPoint(route.destination),
      ];
      final camera = await mapboxMap.cameraForCoordinatesPadding(
        points,
        CameraOptions(bearing: 0, pitch: 0),
        MbxEdgeInsets(top: 130, left: 40, bottom: 230, right: 40),
        MapboxConfig.maxZoom,
        null,
      );

      await mapboxMap.easeTo(
        camera,
        MapAnimationOptions(
          duration: MapboxConfig.animationDuration.inMilliseconds,
        ),
      );
    } catch (error) {
      _setMapError(error);
    }
  }

  Future<void> clearRoute() async {
    activeRoute.value = null;
    destinationController.clear();
    _clearError();
    await _renderMapState();
    await _focusOnCurrentLocation();
  }

  Future<void> openRelevantSettings() async {
    if (_lastErrorType == MapNavigationErrorType.serviceDisabled) {
      await geo.Geolocator.openLocationSettings();
      return;
    }

    if (_lastErrorType == MapNavigationErrorType.permissionPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> retryLastAction() async {
    final errorType = _lastErrorType;
    if (errorType == MapNavigationErrorType.network &&
        destinationController.text.trim().isNotEmpty) {
      await buildRoute();
      return;
    }

    await detectCurrentLocation(forceRefresh: true);
  }

  Future<void> _renderMapState() async {
    if (!isMapReady.value) return;

    try {
      await _routeLineManager?.deleteAll();
      await _markerManager?.deleteAll();
      await _labelManager?.deleteAll();

      final route = activeRoute.value;
      if (route != null) {
        await _routeLineManager?.create(
          PolylineAnnotationOptions(
            geometry: LineString.fromPoints(
              points: route.routePoints.map(_toPoint).toList(growable: false),
            ),
            lineColor: 0xFF1976D2,
            lineOpacity: 0.95,
            lineWidth: 6,
          ),
        );
        await _addMarker(route.origin, 'Current', 0xFF2E7D32);
        await _addMarker(route.destination, 'Destination', 0xFFC62828);
        return;
      }

      final current = currentCoordinate.value;
      if (current != null) {
        await _addMarker(current, 'Current', 0xFF2E7D32);
      }
    } catch (error) {
      _setMapError(error);
    }
  }

  Future<void> _addMarker(
    NavigationCoordinate coordinate,
    String label,
    int color,
  ) async {
    final point = _toPoint(coordinate);
    await _markerManager?.create(
      CircleAnnotationOptions(
        geometry: point,
        circleColor: color,
        circleRadius: 9,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ),
    );

    await _labelManager?.create(
      PointAnnotationOptions(
        geometry: point,
        textField: label,
        textColor: 0xFF111827,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.4,
        textOffset: const [0, 1.4],
        textSize: 12,
      ),
    );
  }

  Future<void> _focusOnCurrentLocation() async {
    final mapboxMap = _mapboxMap;
    final current = currentCoordinate.value;

    if (mapboxMap == null || current == null) {
      return;
    }

    try {
      await mapboxMap.easeTo(
        CameraOptions(
          center: _toPoint(current),
          zoom: MapboxConfig.defaultZoom,
          bearing: 0,
          pitch: 0,
        ),
        MapAnimationOptions(
          duration: MapboxConfig.animationDuration.inMilliseconds,
        ),
      );
    } catch (error) {
      _setMapError(error);
    }
  }

  Point _toPoint(NavigationCoordinate coordinate) {
    return Point(
      coordinates: Position(coordinate.longitude, coordinate.latitude),
    );
  }

  void _setError(MapNavigationException error) {
    _lastErrorType = error.type;
    errorMessage.value = error.message;
    Get.snackbar(
      'Navigation',
      error.message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.shade700,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
    );
  }

  void _setMapError(Object error) {
    _setError(
      MapNavigationException(
        MapNavigationErrorType.mapUnavailable,
        'The map could not be loaded. Check your connection and try again.',
        cause: error,
      ),
    );
  }

  void _clearError() {
    _lastErrorType = null;
    errorMessage.value = '';
  }
}
