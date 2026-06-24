import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/models/navigation_models.dart';
import 'package:geotag_camera/services/map_navigation_service.dart';

void main() {
  group('NavigationRoute formatting', () {
    test('formats short distances in meters', () {
      final route = _route(distanceMeters: 950, durationSeconds: 240);

      expect(route.formattedDistance, '950 m');
      expect(route.formattedDuration, '4 min');
    });

    test('formats longer distances and durations', () {
      final route = _route(distanceMeters: 12400, durationSeconds: 3900);

      expect(route.formattedDistance, '12 km');
      expect(route.formattedDuration, '1h 5min');
    });
  });

  group('MapNavigationService parsing', () {
    test('parses a Mapbox geocoding feature', () {
      final coordinate = MapNavigationService.coordinateFromMapboxFeature(
        <String, dynamic>{
          'place_name': 'Central Park, New York, NY',
          'geometry': <String, dynamic>{
            'coordinates': <num>[-73.9654, 40.7829],
          },
        },
        fallbackLabel: 'Central Park',
      );

      expect(coordinate.latitude, 40.7829);
      expect(coordinate.longitude, -73.9654);
      expect(coordinate.label, 'Central Park, New York, NY');
    });

    test('throws a user-facing exception for missing coordinates', () {
      expect(
        () => MapNavigationService.coordinateFromMapboxFeature(
          <String, dynamic>{'geometry': <String, dynamic>{}},
          fallbackLabel: 'Missing',
        ),
        throwsA(isA<NavigationException>()),
      );
    });

    test('parses a Mapbox directions route', () {
      const origin = NavigationCoordinate(
        latitude: 21.2318,
        longitude: 72.8367,
        label: 'Origin',
      );
      const destination = NavigationCoordinate(
        latitude: 21.25,
        longitude: 72.88,
        label: 'Destination',
      );

      final route = MapNavigationService.routeFromMapboxRoute(
        <String, dynamic>{
          'distance': 5200,
          'duration': 840,
          'geometry': <String, dynamic>{
            'coordinates': <List<num>>[
              <num>[72.8367, 21.2318],
              <num>[72.85, 21.24],
              <num>[72.88, 21.25],
            ],
          },
        },
        origin: origin,
        destination: destination,
      );

      expect(route.path, hasLength(3));
      expect(route.distanceMeters, 5200);
      expect(route.durationSeconds, 840);
      expect(route.path.last.longitude, 72.88);
    });
  });
}

NavigationRoute _route({
  required double distanceMeters,
  required double durationSeconds,
}) {
  const origin = NavigationCoordinate(
    latitude: 1,
    longitude: 1,
    label: 'Origin',
  );
  const destination = NavigationCoordinate(
    latitude: 2,
    longitude: 2,
    label: 'Destination',
  );

  return NavigationRoute(
    origin: origin,
    destination: destination,
    path: const <NavigationCoordinate>[origin, destination],
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
  );
}
