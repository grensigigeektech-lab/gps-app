import 'dart:async';

import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';

class FakeDirections extends MapboxDirectionsService {
  List<NavigationDestination> results = [destination];
  Object? failure;
  int searches = 0;
  int routeCalls = 0;
  Completer<NavigationRoute>? pending;
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
    return results;
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

LocationResult locationResult() => LocationResult.success(
  LocationInfo(latitude: 21, longitude: 72, timestamp: DateTime.now()),
);
