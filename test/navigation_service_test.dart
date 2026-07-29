import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:geotag_camera/services/navigation_service.dart';

void main() {
  const accessToken = 'pk.test-token';

  group('NavigationService geocoding', () {
    test('rejects empty destination input without a network request', () async {
      var requested = false;
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        service.geocodeDestination('   '),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
      expect(requested, isFalse);
    });

    test('returns the first matching Mapbox destination', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient((request) async {
          expect(request.url.path, contains('Pune%20Station.json'));
          expect(request.url.queryParameters['limit'], '1');
          return http.Response('''
            {
              "features": [
                {
                  "place_name": "Pune Railway Station, Pune, India",
                  "center": [73.8746, 18.5289]
                }
              ]
            }
            ''', 200);
        }),
      );

      final result = await service.geocodeDestination('Pune Station');

      expect(result.name, 'Pune Railway Station, Pune, India');
      expect(result.coordinate.latitude, 18.5289);
      expect(result.coordinate.longitude, 73.8746);
    });

    test('reports no match as invalid destination', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient((_) async => http.Response('{"features": []}', 200)),
      );

      expect(
        service.geocodeDestination('not a real place'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });
  });

  group('NavigationService directions', () {
    const origin = NavigationCoordinate(latitude: 21.2, longitude: 72.8);
    const destination = NavigationCoordinate(latitude: 21.3, longitude: 72.9);

    test('parses the route geometry, distance, and travel time', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient((request) async {
          expect(request.url.pathSegments.last, '72.8,21.2;72.9,21.3');
          expect(request.url.queryParameters['geometries'], 'geojson');
          return http.Response('''
            {
              "routes": [
                {
                  "distance": 12500.0,
                  "duration": 4530.0,
                  "geometry": {
                    "type": "LineString",
                    "coordinates": [[72.8, 21.2], [72.85, 21.25], [72.9, 21.3]]
                  }
                }
              ]
            }
            ''', 200);
        }),
      );

      final result = await service.getDrivingRoute(
        origin: origin,
        destination: destination,
      );

      expect(result.coordinates, hasLength(3));
      expect(result.distanceMeters, 12500);
      expect(result.durationSeconds, 4530);
      expect(result.distanceLabel, '12.5 km');
      expect(result.durationLabel, '1 hr 16 min');
    });

    test('reports an empty routes list as no route', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient((_) async => http.Response('{"routes": []}', 200)),
      );

      expect(
        service.getDrivingRoute(origin: origin, destination: destination),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.noRoute,
          ),
        ),
      );
    });
  });

  test('surfaces HTTP failures as a network error', () async {
    final service = NavigationService(
      accessToken: accessToken,
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    expect(
      service.geocodeDestination('Pune'),
      throwsA(
        isA<NavigationException>().having(
          (error) => error.type,
          'type',
          NavigationFailureType.network,
        ),
      ),
    );
  });

  test(
    'fails before requesting when the Mapbox token is not configured',
    () async {
      var requested = false;
      final service = NavigationService(
        accessToken: 'YOUR_MAPBOX_ACCESS_TOKEN',
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        service.geocodeDestination('Pune'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.configuration,
          ),
        ),
      );
      expect(requested, isFalse);
    },
  );
}
