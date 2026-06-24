import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/services/map_navigation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('MapNavigationService', () {
    test('geocodes a valid destination', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((request) async {
          expect(request.url.path, contains('New%20Delhi'));
          return http.Response(
            '{"features":[{"place_name":"New Delhi, India",'
            '"center":[77.209,28.6139]}]}',
            200,
          );
        }),
      );

      final result = await service.geocodeDestination('New Delhi');

      expect(result.name, 'New Delhi, India');
      expect(result.latitude, 28.6139);
      expect(result.longitude, 77.209);
    });

    test('rejects an empty destination without a request', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((_) async => throw StateError('unexpected request')),
      );

      expect(
        () => service.geocodeDestination('   '),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });

    test('reports a destination with no search results', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((_) async => http.Response('{"features":[]}', 200)),
      );

      expect(
        () => service.geocodeDestination('not a place'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });

    test('parses a route, distance, duration and geometry', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((request) async {
          expect(request.url.path, contains('/directions/v5/mapbox/driving/'));
          return http.Response(
            '{"routes":[{"distance":1250.4,"duration":3700,'
            '"geometry":{"coordinates":'
            '[[72.1,21.1],[72.2,21.2],[72.3,21.3]]}}]}',
            200,
          );
        }),
      );

      final route = await service.getDrivingRoute(
        originLatitude: 21.1,
        originLongitude: 72.1,
        destinationLatitude: 21.3,
        destinationLongitude: 72.3,
      );

      expect(route.coordinates, hasLength(3));
      expect(route.distanceMeters, 1250.4);
      expect(route.formattedDistance, '1.3 km');
      expect(route.formattedDuration, '1 hr 2 min');
    });

    test('reports a successful response with no route', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((_) async => http.Response('{"routes":[]}', 200)),
      );

      expect(
        () => service.getDrivingRoute(
          originLatitude: 21.1,
          originLongitude: 72.1,
          destinationLatitude: 21.3,
          destinationLongitude: 72.3,
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

    test('turns HTTP failures into user-facing network errors', () async {
      final service = MapNavigationService(
        accessToken: 'test-token',
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );

      expect(
        () => service.geocodeDestination('New Delhi'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.network,
          ),
        ),
      );
    });

    test('detects a missing production token', () async {
      final service = MapNavigationService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => service.geocodeDestination('New Delhi'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.configuration,
          ),
        ),
      );
    });
  });
}
