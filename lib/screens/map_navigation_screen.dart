import 'dart:async';

import 'package:flutter/material.dart' hide NavigationDestination;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../config/mapbox_config.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('navigation_map'),
            styleUri: MapboxConfig.streetStyle,
            viewport: CameraViewportState(
              center: Point(coordinates: Position(72.8366927, 21.2318378)),
              zoom: 11,
            ),
            onMapCreated: controller.onMapCreated,
            onStyleLoadedListener: (_) => controller.onStyleLoaded(),
            onMapLoadErrorListener: controller.onMapLoadError,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavigationSearchCard(controller: controller),
                  const SizedBox(height: 10),
                  Obx(() => _buildErrorCard()),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(
                      () => FloatingActionButton.small(
                        heroTag: 'current_location',
                        onPressed: controller.isLocating.value
                            ? null
                            : controller.loadCurrentLocation,
                        tooltip: 'Refresh current location',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1565C0),
                        child: controller.isLocating.value
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Obx(() => _buildBottomCard()),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          Obx(
            () => controller.isRouting.value
                ? const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color(0x33000000),
                        child: Center(
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Finding the best driving route…'),
                                ],
                              ),
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
    );
  }

  Widget _buildErrorCard() {
    if (controller.errorMessage.value.isEmpty) {
      return const SizedBox.shrink();
    }

    final actionLabel = controller.errorActionLabel;
    return Material(
      color: const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB3261E)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.errorMessage.value,
                style: const TextStyle(color: Color(0xFF5F1410), fontSize: 13),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: controller.handleErrorAction,
                child: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    final route = controller.route.value;
    final destination = controller.destination.value;
    if (route == null || destination == null) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                controller.currentLocation.value == null
                    ? Icons.location_searching
                    : Icons.gps_fixed,
                color: const Color(0xFF1565C0),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  controller.locationStatus,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Color(0xFFD32F2F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destination.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                _MapLegendItem(color: Color(0xFF1565C0), label: 'Current'),
                SizedBox(width: 18),
                _MapLegendItem(color: Color(0xFFD32F2F), label: 'Destination'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _RouteMetric(
                    icon: Icons.route,
                    label: 'Distance',
                    value: route.distanceLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RouteMetric(
                    icon: Icons.schedule,
                    label: 'Estimated time',
                    value: route.durationLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }
}

class _NavigationSearchCard extends StatelessWidget {
  const _NavigationSearchCard({required this.controller});

  final MapNavigationController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              onPressed: Get.back,
              tooltip: 'Back',
              color: Colors.black87,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('destination_input'),
                controller: controller.destinationController,
                focusNode: controller.destinationFocusNode,
                textInputAction: TextInputAction.go,
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  hintText: 'Enter destination or address',
                  hintStyle: TextStyle(color: Colors.black54),
                  prefixIcon: Icon(Icons.search, color: Color(0xFF1565C0)),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: controller.onDestinationChanged,
                onSubmitted: (_) => controller.findRoute(),
              ),
            ),
            Obx(
              () => IconButton.filled(
                key: const ValueKey('find_route_button'),
                onPressed: controller.isRouting.value
                    ? null
                    : controller.findRoute,
                tooltip: 'Find route',
                icon: const Icon(Icons.directions),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1565C0), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MapNavigationController extends GetxController
    with WidgetsBindingObserver {
  MapNavigationController({NavigationService? navigationService})
    : _navigationService = navigationService ?? NavigationService(),
      _ownsNavigationService = navigationService == null;

  final NavigationService _navigationService;
  final bool _ownsNavigationService;

  final TextEditingController destinationController = TextEditingController();
  final FocusNode destinationFocusNode = FocusNode();

  final Rxn<NavigationCoordinate> currentLocation = Rxn<NavigationCoordinate>();
  final Rxn<NavigationDestination> destination = Rxn<NavigationDestination>();
  final Rxn<NavigationRouteResult> route = Rxn<NavigationRouteResult>();
  final RxBool isLocating = false.obs;
  final RxBool isRouting = false.obs;
  final RxString errorMessage = ''.obs;
  final Rxn<LocationError> locationError = Rxn<LocationError>();
  final Rxn<NavigationFailureType> navigationError =
      Rxn<NavigationFailureType>();

  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _markerManager;
  PolylineAnnotationManager? _routeManager;

  String get locationStatus {
    if (isLocating.value) return 'Detecting your current GPS location…';
    if (currentLocation.value != null) {
      return 'Current location found. Enter a destination to plan a route.';
    }
    return 'Current location is needed before a route can be created.';
  }

  String? get errorActionLabel {
    switch (locationError.value) {
      case LocationError.serviceDisabled:
        return 'GPS settings';
      case LocationError.permissionPermanentlyDenied:
        return 'App settings';
      case LocationError.permissionDenied:
      case LocationError.timeout:
      case LocationError.unknown:
        return 'Retry';
      case null:
        break;
    }

    switch (navigationError.value) {
      case NavigationFailureType.invalidDestination:
        return 'Edit';
      case NavigationFailureType.network:
      case NavigationFailureType.noRoute:
        return 'Retry';
      case NavigationFailureType.configuration:
      case null:
        return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onReady() {
    super.onReady();
    loadCurrentLocation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        locationError.value != null &&
        !isLocating.value) {
      loadCurrentLocation();
    }
  }

  Future<void> loadCurrentLocation() async {
    if (isLocating.value) return;

    isLocating.value = true;
    _clearError();
    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );
    isLocating.value = false;

    if (!result.success || result.info == null) {
      locationError.value = result.error ?? LocationError.unknown;
      errorMessage.value =
          result.errorMessage ??
          'Your current location could not be determined. Please retry.';
      return;
    }

    final info = result.info!;
    currentLocation.value = NavigationCoordinate(
      latitude: info.latitude,
      longitude: info.longitude,
    );
    locationError.value = null;
    await _refreshMapContent();
    if (route.value != null && destinationController.text.trim().isNotEmpty) {
      await findRoute();
    } else {
      await _centerOnCurrentLocation();
    }
  }

  Future<void> findRoute() async {
    if (isRouting.value) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (destinationController.text.trim().isEmpty) {
      navigationError.value = NavigationFailureType.invalidDestination;
      locationError.value = null;
      errorMessage.value = 'Enter a destination to create a route.';
      destinationFocusNode.requestFocus();
      return;
    }

    if (currentLocation.value == null) {
      await loadCurrentLocation();
      if (currentLocation.value == null) return;
    }

    isRouting.value = true;
    _clearError();
    final hadExistingRoute = route.value != null || destination.value != null;
    route.value = null;
    destination.value = null;
    if (hadExistingRoute) await _refreshMapContent();
    try {
      final resolvedDestination = await _navigationService.geocodeDestination(
        destinationController.text,
      );
      final newRoute = await _navigationService.getDrivingRoute(
        origin: currentLocation.value!,
        destination: resolvedDestination.coordinate,
      );

      destination.value = resolvedDestination;
      route.value = newRoute;
      await _refreshMapContent();
    } on NavigationException catch (error) {
      navigationError.value = error.type;
      errorMessage.value = error.message;
      if (error.type == NavigationFailureType.invalidDestination) {
        destinationFocusNode.requestFocus();
      }
    } catch (_) {
      navigationError.value = NavigationFailureType.network;
      errorMessage.value =
          'Navigation could not be loaded. Check your connection and retry.';
    } finally {
      isRouting.value = false;
    }
  }

  void onDestinationChanged(String _) {
    if (route.value != null || destination.value != null) {
      route.value = null;
      destination.value = null;
      unawaited(_refreshMapContent());
    }
    if (navigationError.value == NavigationFailureType.invalidDestination) {
      _clearError();
    }
  }

  Future<void> handleErrorAction() async {
    switch (locationError.value) {
      case LocationError.serviceDisabled:
        await geo.Geolocator.openLocationSettings();
        return;
      case LocationError.permissionPermanentlyDenied:
        await geo.Geolocator.openAppSettings();
        return;
      case LocationError.permissionDenied:
      case LocationError.timeout:
      case LocationError.unknown:
        await loadCurrentLocation();
        return;
      case null:
        break;
    }

    if (navigationError.value == NavigationFailureType.invalidDestination) {
      destinationFocusNode.requestFocus();
      return;
    }
    await findRoute();
  }

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    try {
      _mapboxMap = mapboxMap;
      _markerManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _routeManager = await mapboxMap.annotations
          .createPolylineAnnotationManager();
      await _refreshMapContent();
    } catch (_) {
      navigationError.value = NavigationFailureType.network;
      errorMessage.value =
          'The map could not be prepared. Check your connection and Mapbox token.';
    }
  }

  Future<void> onStyleLoaded() => _refreshMapContent();

  void onMapLoadError(MapLoadingErrorEventData _) {
    if (errorMessage.value.isEmpty) {
      navigationError.value = NavigationFailureType.network;
      errorMessage.value =
          'Map data could not load. Check your connection and Mapbox token.';
    }
  }

  Future<void> _refreshMapContent() async {
    final markerManager = _markerManager;
    final routeManager = _routeManager;
    if (markerManager == null || routeManager == null) return;

    try {
      await markerManager.deleteAll();
      await routeManager.deleteAll();

      final origin = currentLocation.value;
      if (origin != null) {
        await markerManager.create(
          CircleAnnotationOptions(
            geometry: Point(
              coordinates: Position(origin.longitude, origin.latitude),
            ),
            circleColor: 0xFF1565C0,
            circleRadius: 9,
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 3,
          ),
        );
      }

      final resolvedDestination = destination.value;
      if (resolvedDestination != null) {
        final coordinate = resolvedDestination.coordinate;
        await markerManager.create(
          CircleAnnotationOptions(
            geometry: Point(
              coordinates: Position(coordinate.longitude, coordinate.latitude),
            ),
            circleColor: 0xFFD32F2F,
            circleRadius: 9,
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 3,
          ),
        );
      }

      final currentRoute = route.value;
      if (currentRoute == null) return;
      final line = LineString(
        coordinates: currentRoute.coordinates
            .map((point) => Position(point.longitude, point.latitude))
            .toList(growable: false),
      );
      await routeManager.create(
        PolylineAnnotationOptions(
          geometry: line,
          lineColor: 0xFF1565C0,
          lineWidth: 6,
          lineBorderColor: 0xFFFFFFFF,
          lineBorderWidth: 1.5,
          lineJoin: LineJoin.ROUND,
        ),
      );
      await _fitEntireRoute(line);
    } catch (_) {
      if (errorMessage.value.isEmpty) {
        navigationError.value = NavigationFailureType.network;
        errorMessage.value =
            'The route could not be drawn on the map. Please retry.';
      }
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    final mapboxMap = _mapboxMap;
    final origin = currentLocation.value;
    if (mapboxMap == null || origin == null) return;

    await mapboxMap.easeTo(
      CameraOptions(
        center: Point(coordinates: Position(origin.longitude, origin.latitude)),
        zoom: MapboxConfig.defaultZoom,
      ),
      MapAnimationOptions(
        duration: MapboxConfig.animationDuration.inMilliseconds,
      ),
    );
  }

  Future<void> _fitEntireRoute(LineString line) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final camera = await mapboxMap.cameraForGeometry(
      line.toJson(),
      MbxEdgeInsets(top: 150, left: 44, bottom: 250, right: 44),
      0,
      0,
    );
    await mapboxMap.easeTo(
      camera,
      MapAnimationOptions(
        duration: MapboxConfig.animationDuration.inMilliseconds,
      ),
    );
  }

  void _clearError() {
    errorMessage.value = '';
    locationError.value = null;
    navigationError.value = null;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    destinationController.dispose();
    destinationFocusNode.dispose();
    if (_ownsNavigationService) _navigationService.dispose();
    super.onClose();
  }
}
