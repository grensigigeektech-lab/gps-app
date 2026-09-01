import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../services/location_service.dart';
import '../services/mapbox_directions_service.dart';
import '../services/mapbox_service.dart';

enum NavigationPhase { idle, locating, searching, choosing, routing, ready }

class MapNavigationController extends GetxController
    with WidgetsBindingObserver {
  MapNavigationController({
    MapboxDirectionsService? directions,
    MapboxService? map,
    Future<LocationResult> Function()? locate,
    Future<bool> Function()? openAppSettings,
    Future<bool> Function()? openLocationSettings,
    bool? mapsConfigured,
    this.autoLocate = true,
  }) : _directions = directions ?? MapboxDirectionsService(),
       _map = map ?? MapboxService(),
       _locate =
           locate ??
           (() =>
               LocationService.getCurrentLocationResult(reverseGeocode: false)),
       _openAppSettings = openAppSettings ?? LocationService.openAppSettings,
       _openLocationSettings =
           openLocationSettings ?? LocationService.openLocationSettings,
       mapsConfigured = mapsConfigured ?? MapboxConfig.isConfigured;

  final MapboxDirectionsService _directions;
  final MapboxService _map;
  final Future<LocationResult> Function() _locate;
  final Future<bool> Function() _openAppSettings;
  final Future<bool> Function() _openLocationSettings;
  final bool mapsConfigured;
  final bool autoLocate;
  final destinationInput = TextEditingController();
  final phase = NavigationPhase.idle.obs;
  final location = Rxn<LocationInfo>();
  final destination = Rxn<NavigationDestination>();
  final route = Rxn<NavigationRoute>();
  final candidates = <NavigationDestination>[].obs;
  final errorText = ''.obs;
  final locationError = Rxn<LocationError>();
  final mapError = ''.obs;
  final mapLoading = true.obs;
  final mapRevision = 0.obs;
  int _request = 0;
  int _renderRequest = 0;
  bool _closed = false;
  bool _mapCreated = false;
  bool _styleLoaded = false;
  bool _preparingMap = false;
  bool _mapReady = false;
  bool _waitingForSettings = false;
  Timer? _mapTimeout;
  Future<void> _renderQueue = Future.value();

  bool get isBusy =>
      phase.value == NavigationPhase.locating ||
      phase.value == NavigationPhase.searching ||
      phase.value == NavigationPhase.routing;
  bool get canOpenSettings =>
      locationError.value == LocationError.serviceDisabled ||
      locationError.value == LocationError.permissionPermanentlyDenied;
  String get progressLabel => switch (phase.value) {
    NavigationPhase.locating => 'Finding your GPS location…',
    NavigationPhase.searching => 'Finding destination…',
    NavigationPhase.routing => 'Calculating driving route…',
    _ => '',
  };
  RouteCoordinate? get origin => location.value == null
      ? null
      : RouteCoordinate(location.value!.latitude, location.value!.longitude);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    if (mapsConfigured) _startMapTimeout();
    if (autoLocate) unawaited(refreshLocation());
  }

  bool _active(int request) => !_closed && request == _request;

  void destinationChanged(String _) {
    _request++;
    candidates.clear();
    destination.value = null;
    route.value = null;
    errorText.value = '';
    locationError.value = null;
    phase.value = NavigationPhase.idle;
    unawaited(_render());
  }

  Future<void> refreshLocation() async {
    final request = ++_request;
    _resetResult();
    if (await _getLocation(request)) {
      phase.value = NavigationPhase.idle;
      await _render(fit: true);
    }
  }

  void _resetResult() {
    errorText.value = '';
    locationError.value = null;
    candidates.clear();
    route.value = null;
    destination.value = null;
  }

  Future<bool> _getLocation(int request) async {
    phase.value = NavigationPhase.locating;
    location.value = null;
    unawaited(_render());
    try {
      final result = await _locate();
      if (!_active(request)) return false;
      if (!result.success) {
        locationError.value = result.error;
        errorText.value =
            result.errorMessage ?? 'Could not get your location. Please retry.';
        phase.value = NavigationPhase.idle;
        return false;
      }
      location.value = result.info;
      return true;
    } catch (_) {
      if (_active(request)) {
        errorText.value = 'Could not get your location. Check GPS and retry.';
        phase.value = NavigationPhase.idle;
      }
      return false;
    }
  }

  Future<void> search() async {
    final input = destinationInput.text;
    final request = ++_request;
    _resetResult();
    final validation = MapboxDirectionsService.validateDestination(input);
    if (validation != null) {
      errorText.value = validation;
      phase.value = NavigationPhase.idle;
      await _render();
      return;
    }
    if (!mapsConfigured) {
      errorText.value =
          'Maps are not configured. Please contact the app administrator.';
      phase.value = NavigationPhase.idle;
      await _render();
      return;
    }
    if (!await _getLocation(request)) return;
    phase.value = NavigationPhase.searching;
    unawaited(_render(fit: true));
    try {
      final results = await _directions.searchDestinations(
        input,
        proximity: origin,
      );
      if (!_active(request)) return;
      if (results.length == 1) {
        await _calculateRoute(results.single, request);
      } else {
        candidates.assignAll(results);
        phase.value = NavigationPhase.choosing;
      }
    } catch (error) {
      _showFailure(error, request);
    }
  }

  Future<void> selectDestination(NavigationDestination selected) async {
    final request = ++_request;
    _resetResult();
    destination.value = selected;
    if (!await _getLocation(request)) return;
    await _calculateRoute(selected, request);
  }

  Future<void> _calculateRoute(
    NavigationDestination selected,
    int request,
  ) async {
    destination.value = selected;
    candidates.clear();
    phase.value = NavigationPhase.routing;
    unawaited(_render(fit: true));
    try {
      final result = await _directions.getRoute(origin!, selected.coordinate);
      if (!_active(request)) return;
      route.value = result;
      phase.value = NavigationPhase.ready;
      await _render(fit: true);
    } catch (error) {
      _showFailure(error, request);
    }
  }

  void _showFailure(Object error, int request) {
    if (!_active(request)) return;
    route.value = null;
    errorText.value = error is NavigationException
        ? error.message
        : 'Something went wrong while finding your route. Please try again.';
    phase.value = NavigationPhase.idle;
    unawaited(_render());
  }

  Future<void> retry() async {
    if (isBusy) return;
    final selected = destination.value;
    if (selected != null) {
      await selectDestination(selected);
    } else if (destinationInput.text.trim().isNotEmpty) {
      await search();
    } else {
      await refreshLocation();
    }
  }

  Future<void> openSettings() async {
    _waitingForSettings = true;
    try {
      final opened = locationError.value == LocationError.serviceDisabled
          ? await _openLocationSettings()
          : await _openAppSettings();
      if (!_closed && !opened) {
        _waitingForSettings = false;
        errorText.value =
            'Could not open settings. Open device settings manually, then tap Retry.';
      }
    } catch (_) {
      if (!_closed) {
        _waitingForSettings = false;
        errorText.value =
            'Could not open settings. Open device settings manually, then tap Retry.';
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings && !_closed) {
      _waitingForSettings = false;
      unawaited(retry());
    }
  }

  void onMapCreated(MapboxMap map, int revision) {
    if (_closed || revision != mapRevision.value) return;
    _map.setMapController(map);
    _mapCreated = true;
    unawaited(_prepareMap(revision));
  }

  void onStyleLoaded(int revision) {
    if (_closed || revision != mapRevision.value) return;
    _styleLoaded = true;
    unawaited(_prepareMap(revision));
  }

  Future<void> _prepareMap(int revision) async {
    if (!_mapCreated || !_styleLoaded || _preparingMap || _mapReady) return;
    _preparingMap = true;
    try {
      await _map.initializeNavigationAnnotations();
      if (_closed || revision != mapRevision.value) return;
      _mapReady = true;
      _mapTimeout?.cancel();
      mapLoading.value = false;
      mapError.value = '';
      await _render(fit: true);
    } catch (_) {
      onMapError(revision);
    } finally {
      if (revision == mapRevision.value) _preparingMap = false;
    }
  }

  void onMapError(int revision) {
    if (_closed || revision != mapRevision.value) return;
    _mapTimeout?.cancel();
    mapLoading.value = false;
    mapError.value =
        'Could not load the map. Check your connection and map access, then reload.';
  }

  void _startMapTimeout() {
    _mapTimeout?.cancel();
    final revision = mapRevision.value;
    _mapTimeout = Timer(
      const Duration(seconds: 25),
      () => onMapError(revision),
    );
  }

  Future<void> reloadMap() async {
    // Finish any native work before replacing the underlying view.
    _mapReady = false;
    _renderRequest++;
    await _renderQueue;
    if (_closed) return;
    _map.dispose();
    _mapCreated = _styleLoaded = _preparingMap = false;
    mapError.value = '';
    mapLoading.value = true;
    mapRevision.value++;
    _startMapTimeout();
  }

  Future<void> fitRoute() => _render(fit: true);

  Future<void> _render({bool fit = false}) {
    final render = ++_renderRequest;
    final revision = mapRevision.value;
    _renderQueue = _renderQueue.then((_) async {
      if (_closed || !_mapReady || render != _renderRequest) return;
      final start = origin;
      final end = destination.value;
      final path = route.value;
      try {
        await _map.showNavigation(origin: start, destination: end, route: path);
        if (_closed ||
            render != _renderRequest ||
            revision != mapRevision.value) {
          return;
        }
        if (fit && start != null) {
          await _map.fitNavigation(
            origin: start,
            destination: end,
            route: path,
          );
        }
      } catch (_) {
        if (!_closed && revision == mapRevision.value) onMapError(revision);
      }
    });
    return _renderQueue;
  }

  @override
  void onClose() {
    _closed = true;
    _request++;
    _renderRequest++;
    _mapTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    destinationInput.dispose();
    _directions.dispose();
    _map.dispose();
    super.onClose();
  }
}
