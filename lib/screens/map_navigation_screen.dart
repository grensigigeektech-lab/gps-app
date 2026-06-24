import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../services/location_service.dart';
import '../services/mapbox_navigation_service.dart';

enum NavigationViewState { locating, ready, calculating, routeReady, error }

enum NavigationRecoveryAction {
  retryLocation,
  retryRoute,
  openAppSettings,
  openLocationSettings,
}

class MapNavigationController extends GetxController
    with WidgetsBindingObserver {
  MapNavigationController({MapboxNavigationService? navigationService})
    : _navigationService = navigationService ?? MapboxNavigationService();

  final MapboxNavigationService _navigationService;
  final destinationController = TextEditingController();

  final viewState = NavigationViewState.locating.obs;
  final currentLocation = Rxn<NavigationCoordinate>();
  final destination = Rxn<NavigationPlace>();
  final route = Rxn<NavigationRoute>();
  final errorTitle = ''.obs;
  final errorMessage = ''.obs;
  final mapError = ''.obs;
  final recoveryAction = Rxn<NavigationRecoveryAction>();
  final isMapReady = false.obs;

  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  bool _waitingForSettings = false;

  bool get isBusy =>
      viewState.value == NavigationViewState.locating ||
      viewState.value == NavigationViewState.calculating;

  String get recoveryLabel {
    switch (recoveryAction.value) {
      case NavigationRecoveryAction.openAppSettings:
        return 'Open settings';
      case NavigationRecoveryAction.openLocationSettings:
        return 'Enable GPS';
      case NavigationRecoveryAction.retryLocation:
      case NavigationRecoveryAction.retryRoute:
        return 'Try again';
      case null:
        return '';
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadCurrentLocation());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      unawaited(loadCurrentLocation());
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    destinationController.dispose();
    _navigationService.dispose();
    super.onClose();
  }

  Future<void> loadCurrentLocation() async {
    if (viewState.value == NavigationViewState.calculating) {
      return;
    }

    _clearError();
    viewState.value = NavigationViewState.locating;
    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );

    final info = result.info;
    if (info != null) {
      currentLocation.value = NavigationCoordinate(
        latitude: info.latitude,
        longitude: info.longitude,
      );
      viewState.value = route.value == null
          ? NavigationViewState.ready
          : NavigationViewState.routeReady;
      if (route.value == null) {
        await _showCurrentLocation(centerCamera: true);
      }
      return;
    }

    switch (result.error) {
      case LocationError.serviceDisabled:
        _setError(
          title: 'Location is turned off',
          message: result.errorMessage ?? 'Enable GPS to use navigation.',
          action: NavigationRecoveryAction.openLocationSettings,
        );
      case LocationError.permissionPermanentlyDenied:
        _setError(
          title: 'Location permission required',
          message:
              result.errorMessage ??
              'Allow location access in Settings to use navigation.',
          action: NavigationRecoveryAction.openAppSettings,
        );
      case LocationError.permissionDenied:
        _setError(
          title: 'Location permission denied',
          message:
              result.errorMessage ??
              'Location access is required to calculate a route.',
          action: NavigationRecoveryAction.retryLocation,
        );
      case LocationError.timeout:
        _setError(
          title: 'Location unavailable',
          message:
              result.errorMessage ??
              'Could not determine your location. Check your GPS signal.',
          action: NavigationRecoveryAction.retryLocation,
        );
      case LocationError.unknown:
      case null:
        _setError(
          title: 'Location unavailable',
          message:
              result.errorMessage ?? 'An unexpected location error occurred.',
          action: NavigationRecoveryAction.retryLocation,
        );
    }
  }

  Future<void> findRoute() async {
    if (isBusy) {
      return;
    }

    final query = destinationController.text.trim();
    if (query.length < 2) {
      _setError(
        title: 'Enter a destination',
        message: 'Use a place name, landmark, or full address.',
        action: null,
      );
      return;
    }

    if (currentLocation.value == null) {
      await loadCurrentLocation();
      if (currentLocation.value == null) {
        return;
      }
    }

    _clearError();
    viewState.value = NavigationViewState.calculating;
    await _clearRouteAnnotations();
    route.value = null;
    destination.value = null;
    await _showCurrentLocation(centerCamera: false);

    try {
      final resolvedDestination = await _navigationService.geocodeDestination(
        query,
      );
      final resolvedRoute = await _navigationService.getDrivingRoute(
        origin: currentLocation.value!,
        destination: resolvedDestination.coordinate,
      );

      destination.value = resolvedDestination;
      route.value = resolvedRoute;
      viewState.value = NavigationViewState.routeReady;
      await _renderRoute();
    } on NavigationFailure catch (failure) {
      _handleNavigationFailure(failure);
    } catch (_) {
      _setError(
        title: 'Route unavailable',
        message: 'Something went wrong while calculating the route.',
        action: NavigationRecoveryAction.retryRoute,
      );
    }
  }

  Future<void> handleRecovery() async {
    switch (recoveryAction.value) {
      case NavigationRecoveryAction.retryLocation:
        await loadCurrentLocation();
      case NavigationRecoveryAction.retryRoute:
        await findRoute();
      case NavigationRecoveryAction.openAppSettings:
        _waitingForSettings = await LocationService.openAppSettings();
      case NavigationRecoveryAction.openLocationSettings:
        _waitingForSettings = await LocationService.openLocationSettings();
      case null:
        break;
    }
  }

  Future<void> clearRoute() async {
    destinationController.clear();
    destination.value = null;
    route.value = null;
    _clearError();
    viewState.value = currentLocation.value == null
        ? NavigationViewState.locating
        : NavigationViewState.ready;
    await _clearRouteAnnotations();
    await _showCurrentLocation(centerCamera: true);
  }

  void onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  void onStyleLoaded(StyleLoadedEventData _) {
    unawaited(_initializeMapLayers());
  }

  void onMapLoadError(MapLoadingErrorEventData event) {
    if (event.type == MapLoadErrorType.STYLE) {
      mapError.value = MapboxConfig.isConfigured
          ? 'The map could not load. Check your connection and retry.'
          : 'Mapbox is not configured. Add a MAPBOX_ACCESS_TOKEN.';
    }
  }

  Future<void> centerOnCurrentLocation() async {
    final map = _mapboxMap;
    final location = currentLocation.value;
    if (map == null || location == null) {
      await loadCurrentLocation();
      return;
    }

    await map.easeTo(
      CameraOptions(center: _point(location), zoom: MapboxConfig.defaultZoom),
      MapAnimationOptions(duration: 650),
    );
  }

  Future<void> _initializeMapLayers() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    try {
      _polylineAnnotationManager = await map.annotations
          .createPolylineAnnotationManager();
      _pointAnnotationManager = await map.annotations
          .createPointAnnotationManager();
      await _polylineAnnotationManager!.setLineCap(LineCap.ROUND);
      await _pointAnnotationManager!.setIconAllowOverlap(true);
      isMapReady.value = true;
      mapError.value = '';

      if (route.value != null && destination.value != null) {
        await _renderRoute();
      } else if (currentLocation.value != null) {
        await _showCurrentLocation(centerCamera: true);
      }
    } catch (_) {
      mapError.value = 'The map could not prepare the route display.';
    }
  }

  Future<void> _renderRoute() async {
    final map = _mapboxMap;
    final lineManager = _polylineAnnotationManager;
    final pointManager = _pointAnnotationManager;
    final current = currentLocation.value;
    final target = destination.value;
    final activeRoute = route.value;
    if (map == null ||
        lineManager == null ||
        pointManager == null ||
        current == null ||
        target == null ||
        activeRoute == null) {
      return;
    }

    await Future.wait([lineManager.deleteAll(), pointManager.deleteAll()]);

    final routePoints = activeRoute.coordinates.map(_point).toList();
    await lineManager.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: activeRoute.coordinates
              .map(
                (coordinate) =>
                    Position(coordinate.longitude, coordinate.latitude),
              )
              .toList(),
        ),
        lineColor: const Color(0xFF2563EB).toARGB32(),
        lineBorderColor: const Color(0xFFFFFFFF).toARGB32(),
        lineBorderWidth: 2,
        lineJoin: LineJoin.ROUND,
        lineOpacity: 0.95,
        lineWidth: 6,
      ),
    );

    final currentIcon = await _createMarkerImage(
      const Color(0xFF2563EB),
      destinationMarker: false,
    );
    final destinationIcon = await _createMarkerImage(
      const Color(0xFFDC2626),
      destinationMarker: true,
    );
    await pointManager.createMulti([
      _markerOptions(
        coordinate: current,
        label: 'Current location',
        image: currentIcon,
        anchor: IconAnchor.CENTER,
      ),
      _markerOptions(
        coordinate: target.coordinate,
        label: 'Destination',
        image: destinationIcon,
        anchor: IconAnchor.BOTTOM,
      ),
    ]);

    final padding = MbxEdgeInsets(top: 130, left: 48, bottom: 190, right: 48);
    final camera = await map.cameraForCoordinatesPadding(
      routePoints,
      CameraOptions(bearing: 0, pitch: 0, padding: padding),
      padding,
      16,
      null,
    );
    await map.easeTo(camera, MapAnimationOptions(duration: 800));
  }

  Future<void> _showCurrentLocation({required bool centerCamera}) async {
    final manager = _pointAnnotationManager;
    final location = currentLocation.value;
    if (manager == null || location == null || route.value != null) {
      return;
    }

    await manager.deleteAll();
    await manager.create(
      _markerOptions(
        coordinate: location,
        label: 'Current location',
        image: await _createMarkerImage(
          const Color(0xFF2563EB),
          destinationMarker: false,
        ),
        anchor: IconAnchor.CENTER,
      ),
    );
    if (centerCamera) {
      await centerOnCurrentLocation();
    }
  }

  Future<void> _clearRouteAnnotations() async {
    await _polylineAnnotationManager?.deleteAll();
    await _pointAnnotationManager?.deleteAll();
  }

  PointAnnotationOptions _markerOptions({
    required NavigationCoordinate coordinate,
    required String label,
    required Uint8List image,
    required IconAnchor anchor,
  }) {
    return PointAnnotationOptions(
      geometry: _point(coordinate),
      image: image,
      iconAnchor: anchor,
      textField: label,
      textColor: const Color(0xFF111827).toARGB32(),
      textHaloColor: const Color(0xFFFFFFFF).toARGB32(),
      textHaloWidth: 2,
      textOffset: const [0, 2.2],
      textSize: 12,
    );
  }

  Point _point(NavigationCoordinate coordinate) {
    return Point(
      coordinates: Position(coordinate.longitude, coordinate.latitude),
    );
  }

  Future<Uint8List> _createMarkerImage(
    Color color, {
    required bool destinationMarker,
  }) async {
    const size = ui.Size(56, 56);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fill = Paint()..color = color;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    if (destinationMarker) {
      final pin = Path()
        ..moveTo(14, 24)
        ..quadraticBezierTo(14, 8, 28, 8)
        ..quadraticBezierTo(42, 8, 42, 24)
        ..quadraticBezierTo(42, 34, 28, 52)
        ..quadraticBezierTo(14, 34, 14, 24)
        ..close();
      canvas.drawPath(pin, fill);
      canvas.drawPath(pin, border);
      canvas.drawCircle(const Offset(28, 23), 5, Paint()..color = Colors.white);
    } else {
      canvas.drawCircle(
        const Offset(28, 28),
        18,
        Paint()..color = color.withValues(alpha: 0.22),
      );
      canvas.drawCircle(const Offset(28, 28), 11, fill);
      canvas.drawCircle(const Offset(28, 28), 11, border);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Could not create a map marker.');
    }
    return bytes.buffer.asUint8List();
  }

  void _handleNavigationFailure(NavigationFailure failure) {
    switch (failure.type) {
      case NavigationFailureType.invalidInput:
        _setError(
          title: 'Enter a destination',
          message: failure.message,
          action: null,
        );
      case NavigationFailureType.invalidDestination:
        _setError(
          title: 'Destination not found',
          message: failure.message,
          action: NavigationRecoveryAction.retryRoute,
        );
      case NavigationFailureType.noRoute:
        _setError(
          title: 'No route available',
          message: failure.message,
          action: NavigationRecoveryAction.retryRoute,
        );
      case NavigationFailureType.configuration:
        _setError(
          title: 'Map services unavailable',
          message: failure.message,
          action: null,
        );
      case NavigationFailureType.network:
      case NavigationFailureType.invalidResponse:
        _setError(
          title: 'Route unavailable',
          message: failure.message,
          action: NavigationRecoveryAction.retryRoute,
        );
    }
  }

  void _setError({
    required String title,
    required String message,
    required NavigationRecoveryAction? action,
  }) {
    errorTitle.value = title;
    errorMessage.value = message;
    recoveryAction.value = action;
    viewState.value = NavigationViewState.error;
  }

  void _clearError() {
    errorTitle.value = '';
    errorMessage.value = '';
    recoveryAction.value = null;
  }
}

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapWidget(
                key: const ValueKey('navigation_map'),
                styleUri: MapboxConfig.streetStyle,
                viewport: CameraViewportState(
                  center: Point(coordinates: Position(78.9629, 20.5937)),
                  zoom: 3.5,
                ),
                onMapCreated: controller.onMapCreated,
                onStyleLoadedListener: controller.onStyleLoaded,
                onMapLoadErrorListener: controller.onMapLoadError,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildSearchBar(context),
            ),
            Positioned(
              top: 80,
              left: 12,
              right: 12,
              child: Obx(_buildStatusPanel),
            ),
            Positioned(
              right: 16,
              bottom: 128,
              child: Obx(
                () => controller.currentLocation.value == null
                    ? const SizedBox.shrink()
                    : Material(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(8),
                        elevation: 4,
                        child: IconButton(
                          tooltip: 'Center on current location',
                          onPressed: controller.centerOnCurrentLocation,
                          icon: const Icon(Icons.my_location),
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Obx(_buildRouteSummary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Material(
      color: const Color(0xFF171A1F),
      borderRadius: BorderRadius.circular(8),
      elevation: 5,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: Get.back,
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
            ),
            Expanded(
              child: TextField(
                controller: controller.destinationController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  FocusScope.of(context).unfocus();
                  controller.findRoute();
                },
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Where do you want to go?',
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Obx(
              () => SizedBox(
                width: 52,
                height: 52,
                child: controller.isBusy
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF60A5FA),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Find route',
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          controller.findRoute();
                        },
                        icon: const Icon(Icons.directions),
                        color: const Color(0xFF60A5FA),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    final state = controller.viewState.value;
    if (state == NavigationViewState.locating ||
        state == NavigationViewState.calculating) {
      return Material(
        color: const Color(0xFF171A1F),
        borderRadius: BorderRadius.circular(8),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                state == NavigationViewState.locating
                    ? 'Finding your location...'
                    : 'Calculating the best route...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final message = controller.errorMessage.value.isNotEmpty
        ? controller.errorMessage.value
        : controller.mapError.value;
    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.errorTitle.value.isNotEmpty)
                    Text(
                      controller.errorTitle.value,
                      style: const TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF991B1B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (controller.recoveryAction.value != null)
              TextButton(
                onPressed: controller.handleRecovery,
                child: Text(controller.recoveryLabel),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteSummary() {
    final activeRoute = controller.route.value;
    final target = controller.destination.value;
    if (activeRoute == null || target == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFF171A1F),
      borderRadius: BorderRadius.circular(8),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.flag, color: Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${activeRoute.formattedDistance}  |  '
                    '${activeRoute.formattedDuration}',
                    style: const TextStyle(
                      color: Color(0xFFD1D5DB),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Clear route',
              onPressed: controller.clearRoute,
              icon: const Icon(Icons.close),
              color: const Color(0xFFD1D5DB),
            ),
          ],
        ),
      ),
    );
  }
}
