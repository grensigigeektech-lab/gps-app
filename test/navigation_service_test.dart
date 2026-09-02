import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/navigation_service.dart';

final origin = LocationInfo(
  latitude: 21.2,
  longitude: 72.8,
  timestamp: DateTime(2026),
);
const destination = RouteDestination(
  name: 'Destination',
  latitude: 22,
  longitude: 73,
);

Map<String, Object> routeResponse({
  Object? geometry,
  num distance = 1234,
  num duration = 3661,
}) => {
  'code': 'Ok',
  'routes': [
    {
      'distance': distance,
      'duration': duration,
      'geometry':
          geometry ??
          {
            'type': 'LineString',
            'coordinates': [
              [72.8, 21.2],
              [72.9, 23],
              [73, 22],
            ],
          },
    },
  ],
};

Matcher failsWith(NavigationError error) =>
    throwsA(isA<NavigationException>().having((e) => e.error, 'error', error));

NavigationService serviceWith(Object data, {int status = 200}) =>
    NavigationService(
      accessToken: 'pk.test',
      clientFactory: () =>
          MockClient((_) async => http.Response(jsonEncode(data), status)),
    );

void main() {
  test(
    'geocoding encodes input, uses GPS proximity, and returns choices',
    () async {
      final service = NavigationService(
        accessToken: 'pk.test',
        clientFactory: () => MockClient((request) async {
          expect(request.url.path, '/search/geocode/v6/forward');
          expect(request.url.queryParameters['q'], 'Café & Main #2');
          expect(request.url.queryParameters['proximity'], '72.8,21.2');
          expect(request.url.queryParameters['autocomplete'], 'false');
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'properties': {'full_address': 'Café, Main Street'},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [73, 22],
                  },
                },
                {
                  'properties': {'name': 'Other city'},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [74, 23],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final results = await service.findDestinations(
        '  Café & Main #2  ',
        origin,
      );
      expect(results.map((r) => r.name), ['Café, Main Street', 'Other city']);
      expect(results.first.latitude, 22);
      expect(results.first.longitude, 73);
    },
  );

  for (final query in [
    '',
    '   ',
    'a' * 257,
    'Main; Street',
    'a\nstreet',
    List.filled(21, 'x').join(' '),
  ]) {
    test(
      'invalid destination is rejected before HTTP: ${query.length}',
      () async {
        final service = NavigationService(
          clientFactory: () => throw StateError('must not call HTTP'),
        );
        await expectLater(
          service.findDestinations(query, origin),
          failsWith(NavigationError.invalidDestination),
        );
      },
    );
  }

  test('empty destination results are actionable', () async {
    await expectLater(
      serviceWith({'features': []}).findDestinations('Nowhere', origin),
      failsWith(NavigationError.destinationNotFound),
    );
  });

  test('driving directions keep full geometry and use lng/lat order', () async {
    final service = NavigationService(
      accessToken: 'pk.test',
      clientFactory: () => MockClient((request) async {
        expect(
          request.url.path,
          '/directions/v5/mapbox/driving/72.8,21.2;73.0,22.0',
        );
        expect(request.url.queryParameters['overview'], 'full');
        expect(request.url.queryParameters['geometries'], 'geojson');
        return http.Response(jsonEncode(routeResponse()), 200);
      }),
    );
    final route = await service.getRoute(origin, destination);
    expect(route.coordinates, [
      [72.8, 21.2],
      [72.9, 23],
      [73, 22],
    ]);
    expect(route.distanceLabel, '1.2 km');
    expect(route.durationLabel, '1 hr 2 min');
    expect(() => route.coordinates.add([0, 0]), throwsUnsupportedError);
    expect(() => route.coordinates.first[0] = 1, throwsUnsupportedError);
  });

  test('zero distance and same-location route remains valid', () async {
    final route = await serviceWith(
      routeResponse(distance: 0, duration: 0),
    ).getRoute(origin, destination);
    expect(route.distanceLabel, '0 m');
    expect(route.durationLabel, '<1 min');
  });

  for (final data in [
    {'code': 'NoRoute'},
    {'code': 'NoSegment'},
    {'code': 'Ok', 'routes': []},
  ]) {
    test('no route: $data', () async {
      await expectLater(
        serviceWith(data).getRoute(origin, destination),
        failsWith(NavigationError.noRoute),
      );
    });
  }

  for (final entry in {
    401: NavigationError.configuration,
    403: NavigationError.configuration,
    429: NavigationError.rateLimited,
    500: NavigationError.unavailable,
    422: NavigationError.invalidDestination,
  }.entries) {
    test('HTTP ${entry.key} has a safe user-facing error', () async {
      await expectLater(
        serviceWith({}, status: entry.key).getRoute(origin, destination),
        failsWith(entry.value),
      );
    });
  }

  for (final data in [
    {},
    {'code': 'Ok'},
    routeResponse(distance: -1),
    routeResponse(duration: -1),
    routeResponse(
      geometry: {
        'type': 'Point',
        'coordinates': [1, 2],
      },
    ),
    routeResponse(
      geometry: {
        'type': 'LineString',
        'coordinates': [
          [200, 22],
          [73, 22],
        ],
      },
    ),
    routeResponse(
      geometry: {
        'type': 'LineString',
        'coordinates': [
          [73, 22],
        ],
      },
    ),
    routeResponse(
      geometry: {
        'type': 'LineString',
        'coordinates': [
          ['x', 22],
          [73, 22],
        ],
      },
    ),
  ]) {
    test('malformed route response is rejected: $data', () async {
      await expectLater(
        serviceWith(data).getRoute(origin, destination),
        failsWith(NavigationError.invalidResponse),
      );
    });
  }

  test('malformed JSON is rejected', () async {
    final service = NavigationService(
      accessToken: 'pk.test',
      clientFactory: () =>
          MockClient((_) async => http.Response('{broken', 200)),
    );
    await expectLater(
      service.getRoute(origin, destination),
      failsWith(NavigationError.invalidResponse),
    );
  });

  test('network failure does not leak URL/token to the UI', () async {
    final service = NavigationService(
      accessToken: 'pk.test',
      clientFactory: () =>
          MockClient((_) async => throw http.ClientException('secret URL')),
    );
    await expectLater(
      service.getRoute(origin, destination),
      failsWith(NavigationError.network),
    );
    expect(
      const NavigationException(NavigationError.network).message,
      isNot(contains('secret')),
    );
  });

  test('requests time out and release the client', () async {
    final client = TrackingClient();
    final service = NavigationService(
      accessToken: 'pk.test',
      clientFactory: () => client,
      requestTimeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      service.getRoute(origin, destination),
      failsWith(NavigationError.timeout),
    );
    expect(client.closed, isTrue);
  });

  test('missing or secret token is rejected before HTTP', () async {
    for (final token in ['', 'YOUR_MAPBOX_ACCESS_TOKEN', 'sk.secret']) {
      final service = NavigationService(
        accessToken: token,
        clientFactory: () => throw StateError('no HTTP'),
      );
      await expectLater(
        service.getRoute(origin, destination),
        failsWith(NavigationError.configuration),
      );
    }
  });
}

class TrackingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}
