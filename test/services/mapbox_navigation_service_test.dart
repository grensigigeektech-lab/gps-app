import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geotag_camera/services/mapbox_navigation_service.dart';

void main() {
  group('MapboxNavigationService geocoding', () {
    test('returns a destination with coordinates', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.mapbox.com');
        expect(request.url.pathSegments.last, 'Mumbai, India.json');
        expect(request.url.queryParameters['limit'], '1');
        return http.Response(
          '''
          {
            "features": [
              {
                "place_name": "Mumbai, Maharashtra, India",
                "center": [72.8777, 19.0760]
              }
            ]
          }
          ''',
          200,
        );
      });
      final service = MapboxNavigationService(
        client: client,
        accessToken: 'pk.test',
      );

      final result = await service.geocodeDestination('  Mumbai, India  ');

      expect(result.name, 'Mumbai, Maharashtra, India');
      expect(result.coordinate.latitude, 19.0760);
      expect(result.coordinate.longitude, 72.8777);
    });

    test('rejects empty destination input before making a request', () async {
      final service = MapboxNavigationService(
        client: MockClient((_) async => http.Response('{}', 200)),
        accessToken: 'pk.test',
      );

      expect(
        () => service.geocodeDestination(' '),
        throwsA(
          isA<NavigationFailure>().having(
            (failure) => failure.type,
            'type',
            NavigationFailureType.invalidInput,
          ),
        ),
      );
    });

    test('reports a destination that cannot be found', () async {
      final service = MapboxNavigationService(
        client: MockClient(
          (_) async => http.Response('{"features": []}', 200),
        ),
        accessToken: 'pk.test',
      );

      expect(
        () => service.geocodeDestination('Not a real place'),
        throwsA(
          isA<NavigationFailure>().having(
            (failure) => failure.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });
  });

  group('MapboxNavigationService routing', () {
    const origin = NavigationCoordinate(latitude: 21.1702, longitude: 72.8311);
    const destination =
        NavigationCoordinate(latitude: 19.0760, longitude: 72.8777);

    test('parses route geometry, distance, and travel time', () async {
      final client = MockClient((request) async {
        expect(request.url.pathSegments, contains('driving'));
        expect(request.url.queryParameters['geometries'], 'geojson');
        return http.Response(
          '''
          {
            "code": "Ok",
            "routes": [
              {
                "distance": 12400.0,
                "duration": 3900.0,
                "geometry": {
                  "coordinates": [
                    [72.8311, 21.1702],
                    [72.8500, 20.1000],
                    [72.8777, 19.0760]
                  ]
                }
              }
            ]
          }
          ''',
          200,
        );
      });
      final service = MapboxNavigationService(
        client: client,
        accessToken: 'pk.test',
      );

      final result = await service.getDrivingRoute(
        origin: origin,
        destination: destination,
      );

      expect(result.coordinates, hasLength(3));
      expect(result.coordinates.last.latitude, 19.0760);
      expect(result.distanceMeters, 12400.0);
      expect(result.durationSeconds, 3900.0);
      expect(result.formattedDistance, '12.4 km');
      expect(result.formattedDuration, '1 hr 5 min');
    });

    test('reports when no route can be generated', () async {
      final service = MapboxNavigationService(
        client: MockClient(
          (_) async => http.Response('{"code": "NoRoute", "routes": []}', 200),
        ),
        accessToken: 'pk.test',
      );

      expect(
        () => service.getDrivingRoute(
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<NavigationFailure>().having(
            (failure) => failure.type,
            'type',
            NavigationFailureType.noRoute,
          ),
        ),
      );
    });

    test('maps service failures to a network error', () async {
      final service = MapboxNavigationService(
        client: MockClient((_) async => http.Response('Unavailable', 503)),
        accessToken: 'pk.test',
      );

      expect(
        () => service.getDrivingRoute(
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<NavigationFailure>().having(
            (failure) => failure.type,
            'type',
            NavigationFailureType.network,
          ),
        ),
      );
    });

    test('requires a configured access token', () async {
      final service = MapboxNavigationService(
        client: MockClient((_) async => http.Response('{}', 200)),
        accessToken: 'YOUR_MAPBOX_ACCESS_TOKEN',
      );

      expect(
        () => service.getDrivingRoute(
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<NavigationFailure>().having(
            (failure) => failure.type,
            'type',
            NavigationFailureType.configuration,
          ),
        ),
      );
    });
  });
}
