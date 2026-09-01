import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geotag_camera/services/mapbox_directions_service.dart';

Map<String, Object> place(String name, List<num> coordinates) => {
  'type': 'Feature',
  'properties': {'full_address': name},
  'geometry': {'type': 'Point', 'coordinates': coordinates},
};

void main() {
  MapboxDirectionsService service(
    FutureOr<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
    String token = 'pk.test',
  }) {
    final api = MapboxDirectionsService(
      client: MockClient((r) async => handler(r)),
      accessToken: token,
      timeout: timeout,
    );
    addTearDown(api.dispose);
    return api;
  }

  const start = RouteCoordinate(21, 72);
  const end = RouteCoordinate(22, 73);
  Matcher failure(NavigationError error) =>
      isA<NavigationException>().having((e) => e.error, 'error', error);

  test(
    'validates empty, punctuation, controls and overlong input; accepts Unicode',
    () {
      for (final value in [
        '',
        ' ',
        '!',
        'a',
        'a\nb',
        'x' * 257,
        'Surat; Gujarat',
        List.filled(21, 'word').join(' '),
      ]) {
        expect(MapboxDirectionsService.validateDestination(value), isNotNull);
      }
      for (final value in ['Surat', '東京', 'شارع الملك', '12 High Street']) {
        expect(MapboxDirectionsService.validateDestination(value), isNull);
      }
    },
  );

  test(
    'geocodes safely encoded input and returns selectable labeled candidates',
    () async {
      final api = service((request) {
        expect(request.url.host, 'api.mapbox.com');
        expect(request.url.path, '/search/geocode/v6/forward');
        expect(request.url.queryParameters['q'], 'A & B/東京');
        expect(request.url.queryParameters['proximity'], '72.0,21.0');
        expect(request.url.queryParameters['autocomplete'], 'false');
        return http.Response(
          jsonEncode({
            'features': [
              place('Tokyo', [139, 35]),
              place('Tokyo 2', [140, 36]),
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final results = await api.searchDestinations(
        ' A & B/東京 ',
        proximity: start,
      );
      expect(results.map((p) => p.name), ['Tokyo', 'Tokyo 2']);
      expect(results.first.coordinate.latitude, 35);
      expect(results.first.coordinate.longitude, 139);
    },
  );

  test(
    'rejects invalid input before HTTP and reports missing configuration',
    () async {
      final api = service(
        (_) => throw StateError('must not request'),
        token: '',
      );
      await expectLater(
        api.searchDestinations(' '),
        throwsA(failure(NavigationError.invalidDestination)),
      );
      await expectLater(
        api.searchDestinations('Surat'),
        throwsA(failure(NavigationError.configuration)),
      );
    },
  );

  test('reports an unmatched destination', () async {
    final api = service((_) => http.Response('{"features":[]}', 200));
    await expectLater(
      api.searchDestinations('Unknown'),
      throwsA(failure(NavigationError.noDestination)),
    );
  });

  test(
    'reverse geocoding preserves the camera address with a valid v6 query',
    () async {
      final api = service((request) {
        expect(request.url.path, '/search/geocode/v6/reverse');
        expect(request.url.queryParameters['longitude'], '72.0');
        expect(request.url.queryParameters['latitude'], '21.0');
        expect(request.url.queryParameters, isNot(contains('limit')));
        return http.Response(
          jsonEncode({
            'features': [
              place('12 Main Street, Surat', [72, 21]),
            ],
          }),
          200,
        );
      });
      expect(await api.reverseGeocode(start), '12 Main Street, Surat');
    },
  );

  test('an addressless GPS location is valid for the camera', () async {
    final api = service((_) => http.Response('{"features":[]}', 200));
    expect(await api.reverseGeocode(start), isNull);
  });

  test('rejects malformed reverse geocoding data', () async {
    final api = service((_) => http.Response('{"features":[{}]}', 200));
    await expectLater(
      api.reverseGeocode(start),
      throwsA(failure(NavigationError.invalidResponse)),
    );
  });

  test('requests a full road geometry and parses meters and seconds', () async {
    final api = service((request) {
      expect(
        request.url.path,
        '/directions/v5/mapbox/driving/72.0,21.0;73.0,22.0',
      );
      expect(request.url.queryParameters['geometries'], 'geojson');
      expect(request.url.queryParameters['overview'], 'full');
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 2345.0,
              'duration': 3601,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [72, 21],
                  [70, 24],
                  [73, 22],
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final route = await api.getRoute(start, end);
    expect(route.coordinates.length, 3);
    expect(route.coordinates[1].longitude, 70);
    expect(route.distanceLabel, '2.3 km');
    expect(route.durationLabel, '1 hr 1 min');
    expect(() => route.coordinates.clear(), throwsUnsupportedError);
  });

  for (final code in ['NoRoute', 'NoSegment']) {
    test('handles $code even with HTTP 200', () async {
      final api = service(
        (_) => http.Response(jsonEncode({'code': code}), 200),
      );
      await expectLater(
        api.getRoute(start, end),
        throwsA(failure(NavigationError.noRoute)),
      );
    });
  }
  test('handles empty routes', () async {
    final api = service((_) => http.Response('{"code":"Ok","routes":[]}', 200));
    await expectLater(
      api.getRoute(start, end),
      throwsA(failure(NavigationError.noRoute)),
    );
  });
  test('rejects malformed, out-of-range and missing geocoding data', () async {
    for (final body in [
      '<html/>',
      '[]',
      '{}',
      jsonEncode({
        'features': [
          place('Bad', [181, 12]),
        ],
      }),
      jsonEncode({
        'features': [
          place('', [1, 2]),
        ],
      }),
      '{"features":[null]}',
    ]) {
      final api = service((_) => http.Response(body, 200));
      await expectLater(
        api.searchDestinations('Surat'),
        throwsA(failure(NavigationError.invalidResponse)),
      );
    }
  });
  test('rejects invalid route metrics and malformed geometry', () async {
    for (final route in [
      {
        'distance': -1,
        'duration': 10,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [72, 21],
            [73, 22],
          ],
        },
      },
      {
        'distance': 1,
        'duration': '10',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [72, 21],
            [73, 22],
          ],
        },
      },
      {
        'distance': 1,
        'duration': 10,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [72, 91],
            [73, 22],
          ],
        },
      },
      {
        'distance': 1,
        'duration': 10,
        'geometry': {
          'type': 'Point',
          'coordinates': [72, 21],
        },
      },
    ]) {
      final api = service(
        (_) => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [route],
          }),
          200,
        ),
      );
      await expectLater(
        api.getRoute(start, end),
        throwsA(failure(NavigationError.invalidResponse)),
      );
    }
  });
  for (final entry in {
    401: NavigationError.configuration,
    403: NavigationError.configuration,
    429: NavigationError.rateLimited,
    500: NavigationError.service,
    422: NavigationError.service,
  }.entries) {
    test('handles HTTP ${entry.key}', () async {
      final api = service(
        (_) => http.Response('sensitive response', entry.key),
      );
      await expectLater(
        api.getRoute(start, end),
        throwsA(failure(entry.value)),
      );
    });
  }
  test('maps network errors without exposing credentials', () async {
    final api = service(
      (_) => throw http.ClientException('URL includes pk.secret'),
    );
    await expectLater(
      api.searchDestinations('Surat'),
      throwsA(
        isA<NavigationException>()
            .having((e) => e.error, 'error', NavigationError.network)
            .having((e) => e.message, 'message', isNot(contains('pk.secret'))),
      ),
    );
  });
  test('bounds request time', () async {
    final pending = Completer<http.Response>();
    final api = service(
      (_) => pending.future,
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      api.getRoute(start, end),
      throwsA(failure(NavigationError.timeout)),
    );
    pending.complete(http.Response('{}', 200));
  });
  test('formats short and hour-long trips', () {
    expect(
      NavigationRoute(
        coordinates: [],
        distanceMeters: 120,
        durationSeconds: 0,
      ).durationLabel,
      '1 min',
    );
    expect(
      NavigationRoute(
        coordinates: [],
        distanceMeters: 120,
        durationSeconds: 3600,
      ).durationLabel,
      '1 hr',
    );
    expect(
      NavigationRoute(
        coordinates: [],
        distanceMeters: 120,
        durationSeconds: 60,
      ).distanceLabel,
      '120 m',
    );
  });
}
