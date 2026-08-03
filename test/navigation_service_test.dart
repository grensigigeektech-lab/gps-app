import 'dart:async';

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

    test('uses the input when the destination label is missing', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response(
            '{"features": [{"center": [73.8746, 18.5289]}]}',
            200,
          ),
        ),
      );

      final result = await service.geocodeDestination('  Pune Station  ');

      expect(result.name, 'Pune Station');
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

    test('rejects destination coordinates outside the valid range', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response(
            '{"features": [{"place_name": "Invalid", "center": [181, 91]}]}',
            200,
          ),
        ),
      );

      expect(
        service.geocodeDestination('Invalid'),
        throwsA(
          isA<NavigationException>().having(
            (error) => error.type,
            'type',
            NavigationFailureType.invalidDestination,
          ),
        ),
      );
    });

    test(
      'reports rejected geocoding requests as invalid destinations',
      () async {
        final service = NavigationService(
          accessToken: accessToken,
          client: MockClient(
            (_) async => http.Response('{"message": "Bad query"}', 422),
          ),
        );

        expect(
          service.geocodeDestination('Invalid address'),
          throwsA(
            isA<NavigationException>().having(
              (error) => error.type,
              'type',
              NavigationFailureType.invalidDestination,
            ),
          ),
        );
      },
    );
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

    test(
      'rejects invalid current GPS coordinates before making a request',
      () async {
        var requested = false;
        final service = NavigationService(
          accessToken: accessToken,
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(
          service.getDrivingRoute(
            origin: const NavigationCoordinate(latitude: 95, longitude: 72.8),
            destination: destination,
          ),
          throwsA(
            isA<NavigationException>().having(
              (error) => error.type,
              'type',
              NavigationFailureType.noRoute,
            ),
          ),
        );
        expect(requested, isFalse);
      },
    );

    test(
      'rejects invalid destination coordinates before making a request',
      () async {
        var requested = false;
        final service = NavigationService(
          accessToken: accessToken,
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(
          service.getDrivingRoute(
            origin: origin,
            destination: const NavigationCoordinate(
              latitude: 21.3,
              longitude: 181,
            ),
          ),
          throwsA(
            isA<NavigationException>().having(
              (error) => error.type,
              'type',
              NavigationFailureType.invalidDestination,
            ),
          ),
        );
        expect(requested, isFalse);
      },
    );

    test('reports Mapbox NoRoute HTTP responses as no route', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response('{"code": "NoRoute"}', 422),
        ),
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

    test('reports Mapbox NoSegment HTTP responses as no route', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response('{"code": "NoSegment"}', 422),
        ),
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

    test('rejects negative route distance or duration', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response('''
            {
              "routes": [
                {
                  "distance": -1,
                  "duration": 20,
                  "geometry": {
                    "coordinates": [[72.8, 21.2], [72.9, 21.3]]
                  }
                }
              ]
            }
            ''', 200),
        ),
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

    test('rejects routes without two valid geometry coordinates', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response('''
            {
              "routes": [
                {
                  "distance": 10,
                  "duration": 20,
                  "geometry": {
                    "coordinates": [[72.8, 21.2], [181, 95]]
                  }
                }
              ]
            }
            ''', 200),
        ),
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

    test('rejects malformed intermediate route coordinates', () async {
      final service = NavigationService(
        accessToken: accessToken,
        client: MockClient(
          (_) async => http.Response('''
            {
              "routes": [
                {
                  "distance": 10,
                  "duration": 20,
                  "geometry": {
                    "coordinates": [[72.8, 21.2], [181, 95], [72.9, 21.3]]
                  }
                }
              ]
            }
            ''', 200),
        ),
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

  test('surfaces malformed responses as a network error', () async {
    final service = NavigationService(
      accessToken: accessToken,
      client: MockClient((_) async => http.Response('not-json', 200)),
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

  test('surfaces request timeouts as a network error', () async {
    final service = NavigationService(
      accessToken: accessToken,
      requestTimeout: const Duration(milliseconds: 1),
      client: MockClient((_) => Completer<http.Response>().future),
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

  test('surfaces rejected access tokens as configuration errors', () async {
    final service = NavigationService(
      accessToken: accessToken,
      client: MockClient((_) async => http.Response('unauthorized', 401)),
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
  });

  test('surfaces rate limiting as a retryable network error', () async {
    final service = NavigationService(
      accessToken: accessToken,
      client: MockClient((_) async => http.Response('rate limited', 429)),
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
