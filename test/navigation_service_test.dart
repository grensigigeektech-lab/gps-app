import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:geotag_camera/models/navigation_models.dart';
import 'package:geotag_camera/services/navigation_service.dart';

void main() {
  group('NavigationService', () {
    test('geocodes a destination and parses coordinates', () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient((request) async {
          expect(request.url.path, contains('New%20Delhi'));
          return http.Response(
            '{"features":[{"place_name":"New Delhi, India",'
            '"center":[77.2090,28.6139]}]}',
            200,
          );
        }),
      );

      final destination = await service.geocodeDestination('New Delhi');

      expect(destination.name, 'New Delhi, India');
      expect(destination.coordinate.latitude, 28.6139);
      expect(destination.coordinate.longitude, 77.2090);
    });

    test('findRoute returns route geometry, distance, and duration', () async {
      var requestCount = 0;
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient((request) async {
          requestCount += 1;
          if (requestCount == 1) {
            return http.Response(
              '{"features":[{"place_name":"Destination",'
              '"center":[72.90,21.20]}]}',
              200,
            );
          }
          expect(request.url.path, contains('/directions/v5/mapbox/driving/'));
          return http.Response(
            '{"code":"Ok","routes":[{"distance":12345.0,'
            '"duration":3720.0,"geometry":{"type":"LineString",'
            '"coordinates":[[72.83,21.23],[72.86,21.22],'
            '[72.90,21.20]]}}]}',
            200,
          );
        }),
      );

      final route = await service.findRoute(
        origin: const NavigationCoordinate(latitude: 21.23, longitude: 72.83),
        destinationInput: 'Destination',
      );

      expect(route.coordinates, hasLength(3));
      expect(route.formattedDistance, '12.3 km');
      expect(route.formattedDuration, '1 hr 2 min');
    });

    test('rejects short destination input before making a request', () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        service.geocodeDestination('  x '),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });

    test('reports a destination that cannot be found', () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient((_) async => http.Response('{"features":[]}', 200)),
      );

      await expectLater(
        service.geocodeDestination('Unknown destination'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });

    test('reports when no driving route is available', () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient(
          (_) async => http.Response('{"code":"NoRoute","routes":[]}', 200),
        ),
      );

      await expectLater(
        service.getDrivingRoute(
          origin: const NavigationCoordinate(latitude: 0, longitude: 0),
          destination: const GeocodedDestination(
            name: 'Across the ocean',
            coordinate: NavigationCoordinate(latitude: 1, longitude: 1),
          ),
        ),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.noRoute,
          ),
        ),
      );
    });

    test('maps HTTP failures to a network error', () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        client: MockClient((_) async => http.Response('Unavailable', 503)),
      );

      await expectLater(
        service.geocodeDestination('New Delhi'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.network,
          ),
        ),
      );
    });

    test('reports a missing Mapbox token', () async {
      final service = NavigationService(
        accessToken: 'YOUR_MAPBOX_ACCESS_TOKEN',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        service.geocodeDestination('New Delhi'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.mapConfiguration,
          ),
        ),
      );
    });
  });
}
