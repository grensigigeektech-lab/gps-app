import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/models/map_navigation.dart';

void main() {
  group('NavigationRoute formatting', () {
    const destination = NavigationDestination(
      name: 'Central Station',
      coordinate: NavigationCoordinate(latitude: 1, longitude: 2),
    );

    test('formats short routes in metres and minutes', () {
      const route = NavigationRoute(
        destination: destination,
        coordinates: [],
        distanceMeters: 850.4,
        durationSeconds: 125,
      );

      expect(route.formattedDistance, '850 m');
      expect(route.formattedDuration, '3 min');
    });

    test('formats longer routes in kilometres and hours', () {
      const route = NavigationRoute(
        destination: destination,
        coordinates: [],
        distanceMeters: 12450,
        durationSeconds: 5520,
      );

      expect(route.formattedDistance, '12.4 km');
      expect(route.formattedDuration, '1 hr 32 min');
    });
  });
}
