import 'dart:async';

import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';
import 'package:geotag_camera/services/mapbox_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as maps;

class FakeDirections extends MapboxDirectionsService {
  List<NavigationDestination> results = [destination];
  Object? failure;
  int searches = 0;
  int routeCalls = 0;
  Completer<NavigationRoute>? pending;
  Completer<List<NavigationDestination>>? pendingSearch;
  static const destination = NavigationDestination(
    name: 'Destination',
    coordinate: RouteCoordinate(22, 73),
  );
  static NavigationRoute get path => NavigationRoute(
    coordinates: const [RouteCoordinate(21, 72), RouteCoordinate(22, 73)],
    distanceMeters: 1500,
    durationSeconds: 600,
  );
  @override
  Future<List<NavigationDestination>> searchDestinations(
    String input, {
    RouteCoordinate? proximity,
  }) async {
    searches++;
    return pendingSearch == null ? results : pendingSearch!.future;
  }

  @override
  Future<NavigationRoute> getRoute(
    RouteCoordinate origin,
    RouteCoordinate destination,
  ) async {
    routeCalls++;
    if (failure != null) throw failure!;
    return pending == null ? path : pending!.future;
  }
}

class FakeMapController extends Fake implements maps.MapboxMap {}

class FakeNavigationMap extends MapboxService {
  int preparations = 0;
  int fits = 0;
  int renders = 0;
  NavigationRoute? displayedRoute;
  RouteCoordinate? displayedOrigin;
  Completer<void>? pendingPreparation;
  Completer<void>? pendingRender;

  @override
  Future<void> initializeNavigationAnnotations() async {
    preparations++;
    await pendingPreparation?.future;
  }

  @override
  Future<void> showNavigation({
    RouteCoordinate? origin,
    NavigationDestination? destination,
    NavigationRoute? route,
  }) async {
    renders++;
    await pendingRender?.future;
    displayedRoute = route;
    displayedOrigin = origin;
  }

  @override
  Future<void> fitNavigation({
    required RouteCoordinate origin,
    NavigationDestination? destination,
    NavigationRoute? route,
  }) async {
    fits++;
  }
}

LocationResult locationResult() => LocationResult.success(
  LocationInfo(latitude: 21, longitude: 72, timestamp: DateTime.now()),
);
