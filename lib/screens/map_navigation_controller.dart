import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../services/location_service.dart';
import '../services/mapbox_service.dart';
import '../services/navigation_service.dart';

enum NavigationStage {
  idle,
  locating,
  searching,
  choosing,
  routing,
  ready,
  error,
}

class MapNavigationController extends GetxController
    with WidgetsBindingObserver {
  MapNavigationController({
    NavigationService? navigationService,
    Future<LocationResult> Function()? locate,
    Future<bool> Function()? openAppSettings,
    Future<bool> Function()? openLocationSettings,
    this.configured = false,
    this.locateOnInit = true,
    MapboxService Function()? mapServiceFactory,
  }) : _navigation = navigationService ?? NavigationService(),
       _locate =
           locate ??
           (() => LocationService.getCurrentLocationResult(
             forceRefresh: true,
             includeAddress: false,
           )),
       _openAppSettings = openAppSettings ?? Geolocator.openAppSettings,
       _openLocationSettings =
           openLocationSettings ?? Geolocator.openLocationSettings,
       _mapServiceFactory = mapServiceFactory ?? MapboxService.new;

  final NavigationService _navigation;
  final Future<LocationResult> Function() _locate;
  final Future<bool> Function() _openAppSettings;
  final Future<bool> Function() _openLocationSettings;
  final MapboxService Function() _mapServiceFactory;
  final bool configured;
  final bool locateOnInit;
  final destinationInput = TextEditingController();
  final stage = NavigationStage.idle.obs;
  final location = Rxn<LocationInfo>();
  final destination = Rxn<RouteDestination>();
  final route = Rxn<NavigationRoute>();
  final candidates = <RouteDestination>[].obs;
  final message = RxnString();
  final locationError = Rxn<LocationError>();
  final mapError = RxnString();
  final mapLoading = true.obs;
  final mapVersion = 0.obs;

  MapboxService? _mapService;
  bool _styleReady = false;
  bool _returningFromSettings = false;
  bool _locating = false;
  int _request = 0;
  int _renderRevision = 0;
  Future<void> _renderQueue = Future.value();
  Timer? _mapTimer;

  bool get busy =>
      stage.value == NavigationStage.locating ||
      stage.value == NavigationStage.searching ||
      stage.value == NavigationStage.routing;

  String get progressLabel => switch (stage.value) {
    NavigationStage.locating => 'Finding your GPS location…',
    NavigationStage.searching => 'Searching destinations…',
    NavigationStage.routing => 'Finding a driving route…',
    _ => '',
  };

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    if (!configured) {
      mapLoading.value = false;
      message.value = const NavigationException(
        NavigationError.configuration,
      ).message;
      stage.value = NavigationStage.error;
    } else {
      _startMapTimer();
      if (locateOnInit) unawaited(refreshLocation());
    }
  }

  int _begin(NavigationStage next) {
    _navigation.cancelPending();
    _request++;
    message.value = null;
    locationError.value = null;
    stage.value = next;
    return _request;
  }

  bool _active(int request) => !isClosed && request == _request;

  void destinationChanged(String _) {
    // Invalidate old work without opening overlapping GPS permission dialogs.
    // No network requests are made per keystroke.
    if (!configured) {
      candidates.clear();
      destination.value = null;
      route.value = null;
      return;
    }
    if (_locating) {
      _request++;
    } else {
      _begin(NavigationStage.idle);
    }
    candidates.clear();
    destination.value = null;
    route.value = null;
    _render(fitCamera: false);
  }

  Future<bool> _readLocation(int request) async {
    _locating = true;
    location.value = null;
    try {
      final result = await _locate();
      if (!_active(request)) return false;
      if (!result.success) {
        locationError.value = result.error;
        message.value = result.errorMessage;
        stage.value = NavigationStage.error;
        _render();
        return false;
      }
      location.value = result.info;
      _render();
      return true;
    } catch (_) {
      if (_active(request)) {
        message.value = 'Could not determine your location. Please retry.';
        stage.value = NavigationStage.error;
      }
      return false;
    } finally {
      _locating = false;
      if (!isClosed &&
          request != _request &&
          stage.value == NavigationStage.locating) {
        stage.value = NavigationStage.idle;
      }
    }
  }

  Future<void> refreshLocation() async {
    if (!configured || busy || _locating) return;
    final request = _begin(NavigationStage.locating);
    route.value = null;
    destination.value = null;
    candidates.clear();
    location.value = null;
    _render();
    if (await _readLocation(request) && _active(request)) {
      stage.value = NavigationStage.idle;
    }
  }

  Future<void> search() async {
    if (!configured || busy || _locating) return;
    final query = destinationInput.text.trim();
    final validation = NavigationService.validateDestination(query);
    final request = _begin(NavigationStage.locating);
    route.value = null;
    destination.value = null;
    candidates.clear();
    _render(fitCamera: false);
    if (validation != null) {
      message.value = validation;
      stage.value = NavigationStage.error;
      return;
    }
    // Always refresh GPS before a new search; never route from an old fix.
    if (!await _readLocation(request) || !_active(request)) return;
    // The input may have changed while the OS permission dialog was visible.
    if (destinationInput.text.trim() != query) {
      stage.value = NavigationStage.idle;
      return;
    }
    stage.value = NavigationStage.searching;
    try {
      final results = await _navigation.findDestinations(
        query,
        location.value!,
      );
      if (!_active(request)) return;
      candidates.assignAll(results);
      stage.value = NavigationStage.choosing;
    } on NavigationException catch (error) {
      _fail(request, error.message);
    } catch (_) {
      _fail(request, 'Could not search destinations. Please retry.');
    }
  }

  Future<void> selectDestination(RouteDestination selected) async {
    if (busy || _locating || !configured) return;
    final request = _begin(NavigationStage.locating);
    destination.value = selected;
    candidates.clear();
    route.value = null;
    // Selection can happen long after search, so refresh GPS and permissions.
    if (!await _readLocation(request) || !_active(request)) return;
    stage.value = NavigationStage.routing;
    _render();
    try {
      final result = await _navigation.getRoute(location.value!, selected);
      if (!_active(request)) return;
      route.value = result;
      stage.value = NavigationStage.ready;
      _render();
    } on NavigationException catch (error) {
      _fail(request, error.message);
    } catch (_) {
      _fail(request, 'Could not calculate a route. Please retry.');
    }
  }

  void _fail(int request, String error) {
    if (!_active(request)) return;
    route.value = null;
    message.value = error;
    stage.value = NavigationStage.error;
    _render(fitCamera: false);
  }

  Future<void> retry() async {
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
    if (busy) return;
    _returningFromSettings = true;
    try {
      final opened = locationError.value == LocationError.serviceDisabled
          ? await _openLocationSettings()
          : await _openAppSettings();
      if (!opened && !isClosed) {
        _returningFromSettings = false;
        message.value =
            'Could not open Settings. Open your device Settings, then retry.';
      }
    } catch (_) {
      _returningFromSettings = false;
      if (!isClosed) message.value = 'Open your device Settings, then retry.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _returningFromSettings &&
        !isClosed) {
      _returningFromSettings = false;
      unawaited(retry());
    }
  }

  void onMapCreated(MapboxMap map, int version) {
    if (isClosed || version != mapVersion.value) return;
    _mapService?.dispose();
    _mapService = _mapServiceFactory()..setMapController(map);
    if (_styleReady) _render();
  }

  void onStyleLoaded(int version) {
    if (isClosed || version != mapVersion.value) return;
    _mapTimer?.cancel();
    _styleReady = true;
    mapLoading.value = false;
    mapError.value = null;
    _render();
  }

  void onMapLoadError(int version) {
    if (isClosed || version != mapVersion.value) return;
    _mapTimer?.cancel();
    mapLoading.value = false;
    mapError.value =
        'Could not load the map. Check your connection and retry the map.';
  }

  void _startMapTimer() {
    _mapTimer?.cancel();
    final version = mapVersion.value;
    _mapTimer = Timer(
      const Duration(seconds: 20),
      () => onMapLoadError(version),
    );
  }

  void retryMap() {
    if (!configured) return;
    _renderRevision++;
    _styleReady = false;
    _mapService?.dispose();
    _mapService = null;
    mapError.value = null;
    mapLoading.value = true;
    mapVersion.value++;
    _startMapTimer();
  }

  void fitRoute() => _render();

  void _render({bool fitCamera = true}) {
    final revision = ++_renderRevision;
    final service = _mapService;
    if (!_styleReady || service == null || isClosed) return;
    final origin = location.value;
    final selected = destination.value;
    final currentRoute = route.value;
    // Serial native map writes keep older annotations from winning a race.
    _renderQueue = _renderQueue.then((_) async {
      if (isClosed || revision != _renderRevision || service != _mapService) {
        return;
      }
      try {
        await service
            .renderNavigation(
              origin: origin,
              destination: selected,
              route: currentRoute,
              fitCamera: fitCamera,
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        if (!isClosed && revision == _renderRevision) {
          mapError.value = 'Could not draw the route. Please retry the map.';
        }
      }
    });
  }

  @override
  void onClose() {
    _request++;
    _renderRevision++;
    _mapTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _navigation.dispose();
    _mapService?.dispose();
    destinationInput.dispose();
    super.onClose();
  }
}

class MapNavigationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => MapNavigationController(configured: MapboxConfig.isConfigured),
    );
  }
}
