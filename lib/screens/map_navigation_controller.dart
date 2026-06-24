import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../services/location_service.dart';
import '../services/map_navigation_service.dart';

enum NavigationViewState { locating, ready, loadingRoute, routeReady, error }

class MapNavigationController extends GetxController {
  MapNavigationController({MapNavigationService? navigationService})
      : _navigationService = navigationService ?? MapNavigationService();

  final MapNavigationService _navigationService;
  final destinationController = TextEditingController();

  final viewState = NavigationViewState.locating.obs;
  final errorMessage = ''.obs;
  final currentLocation = Rxn<LocationInfo>();
  final destination = Rxn<GeocodedDestination>();
  final route = Rxn<NavigationRoute>();
  final mapReady = false.obs;
  final isSettingsActionAvailable = false.obs;

  MapboxMap? _map;
  PointAnnotationManager? _pointManager;
  CircleAnnotationManager? _circleManager;
  PolylineAnnotationManager? _lineManager;

  bool get isBusy =>
      viewState.value == NavigationViewState.locating ||
      viewState.value == NavigationViewState.loadingRoute;

  @override
  void onInit() {
    super.onInit();
    locateUser();
  }

  Future<void> onMapCreated(MapboxMap map) async {
    _map = map;
    _pointManager = await map.annotations.createPointAnnotationManager();
    _circleManager = await map.annotations.createCircleAnnotationManager();
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    mapReady.value = true;
    await _renderMapState();
  }

  Future<void> locateUser() async {
    viewState.value = NavigationViewState.locating;
    errorMessage.value = '';
    isSettingsActionAvailable.value = false;
    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );
    if (!result.success || result.info == null) {
      _showLocationFailure(result);
      return;
    }
    currentLocation.value = result.info;
    viewState.value = NavigationViewState.ready;
    await _renderMapState();
  }

  Future<void> createRoute() async {
    if (isBusy) return;
    final origin = currentLocation.value;
    if (origin == null) {
      await locateUser();
      if (currentLocation.value == null) return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    viewState.value = NavigationViewState.loadingRoute;
    errorMessage.value = '';
    isSettingsActionAvailable.value = false;
    route.value = null;
    destination.value = null;

    try {
      final resolvedDestination = await _navigationService
          .geocodeDestination(destinationController.text);
      final current = currentLocation.value!;
      final calculatedRoute = await _navigationService.getDrivingRoute(
        originLatitude: current.latitude,
        originLongitude: current.longitude,
        destinationLatitude: resolvedDestination.latitude,
        destinationLongitude: resolvedDestination.longitude,
      );
      destination.value = resolvedDestination;
      route.value = calculatedRoute;
      viewState.value = NavigationViewState.routeReady;
      await _renderMapState();
    } on NavigationException catch (error) {
      errorMessage.value = error.message;
      viewState.value = NavigationViewState.error;
      await _renderMapState();
    } catch (_) {
      errorMessage.value =
          'Something went wrong while creating the route. Please try again.';
      viewState.value = NavigationViewState.error;
    }
  }

  void clearRoute() {
    destinationController.clear();
    destination.value = null;
    route.value = null;
    errorMessage.value = '';
    viewState.value = currentLocation.value == null
        ? NavigationViewState.locating
        : NavigationViewState.ready;
    _renderMapState();
  }

  Future<void> openSettings() async {
    final error = errorMessage.value.toLowerCase();
    if (error.contains('gps') || error.contains('location services')) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  void _showLocationFailure(LocationResult result) {
    errorMessage.value = result.errorMessage ??
        'Could not get your current location. Please try again.';
    isSettingsActionAvailable.value =
        result.error == LocationError.serviceDisabled ||
            result.error == LocationError.permissionPermanentlyDenied;
    viewState.value = NavigationViewState.error;
  }

  Future<void> _renderMapState() async {
    final map = _map;
    final pointManager = _pointManager;
    final circleManager = _circleManager;
    final lineManager = _lineManager;
    if (map == null ||
        pointManager == null ||
        circleManager == null ||
        lineManager == null) {
      return;
    }

    await pointManager.deleteAll();
    await circleManager.deleteAll();
    await lineManager.deleteAll();
    final origin = currentLocation.value;
    if (origin == null) return;

    final originPoint = Point(
      coordinates: Position(origin.longitude, origin.latitude),
    );
    await circleManager.create(
      CircleAnnotationOptions(
        geometry: originPoint,
        circleColor: Colors.blue.toARGB32(),
        circleRadius: 8,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
    );
    await pointManager.create(
      PointAnnotationOptions(
        geometry: originPoint,
        textField: 'Current location',
        textColor: Colors.blue.toARGB32(),
        textHaloColor: Colors.white.toARGB32(),
        textHaloWidth: 2,
        textOffset: [0, -1.5],
        textSize: 13,
      ),
    );

    final selectedDestination = destination.value;
    final selectedRoute = route.value;
    if (selectedDestination == null || selectedRoute == null) {
      await map.flyTo(
        CameraOptions(center: originPoint, zoom: 14),
        MapAnimationOptions(duration: 650),
      );
      return;
    }

    final destinationPoint = Point(
      coordinates: Position(
        selectedDestination.longitude,
        selectedDestination.latitude,
      ),
    );
    await circleManager.create(
      CircleAnnotationOptions(
        geometry: destinationPoint,
        circleColor: Colors.red.toARGB32(),
        circleRadius: 8,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
    );
    await pointManager.create(
      PointAnnotationOptions(
        geometry: destinationPoint,
        textField: 'Destination',
        textColor: Colors.red.toARGB32(),
        textHaloColor: Colors.white.toARGB32(),
        textHaloWidth: 2,
        textOffset: [0, -1.5],
        textSize: 13,
      ),
    );
    await lineManager.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: selectedRoute.coordinates),
        lineColor: Colors.blueAccent.toARGB32(),
        lineWidth: 6,
        lineBorderColor: Colors.white.toARGB32(),
        lineBorderWidth: 1.5,
        lineOpacity: 0.92,
      ),
    );

    final routePoints = selectedRoute.coordinates
        .map((position) => Point(coordinates: position))
        .toList(growable: false);
    final camera = await map.cameraForCoordinatesPadding(
      routePoints,
      CameraOptions(),
      MbxEdgeInsets(top: 160, left: 48, bottom: 210, right: 48),
      16,
      null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 900));
  }

  @override
  void onClose() {
    destinationController.dispose();
    _navigationService.dispose();
    super.onClose();
  }
}
