# Mapbox setup and navigation verification

## Configuration

Use the existing Mapbox Maps Flutter SDK (`mapbox_maps_flutter`, locked at 2.23.0).
The application reads its public token at build time:

```sh
flutter pub get
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.YOUR_PUBLIC_TOKEN
flutter build apk --dart-define=MAPBOX_ACCESS_TOKEN=pk.YOUR_PUBLIC_TOKEN
```

Use a public token enabled for the Maps SDK, Geocoding API and Directions API.
Do not embed a secret (`sk.`) token in Dart, Android resources, or Info.plist.
The public client token is included in the compiled application; configure
appropriate account restrictions and usage monitoring. A missing or rejected
public token produces an actionable error, not an endless loading indicator.

The existing Android Gradle configuration supports `MAPBOX_DOWNLOADS_TOKEN` as
a local Gradle property if a native SDK download requires authentication. Keep
any such build-only secret outside version control; it is not the public runtime
token. Android/iOS development toolchains are required for device builds. The existing
Mapbox 2.23.0 dependency requires iOS 14.0; all iOS deployment targets are aligned.

## Architecture

- The camera remains the initial GetX route. **Map Data** opens
  `/map_navigation` using `MapNavigationBinding` and `MapNavigationController`.
- `LocationService` is the shared Geolocator permission/GPS implementation;
  `MapboxLocationService` keeps the existing camera-facing API. Navigation uses
  fresh GPS, never a fabricated coordinate or a cached fallback; native fixes
  older than two minutes are rejected. Concurrent callers share permission prompts
  and the in-flight GPS request. Reverse geocoding uses the same Mapbox API client,
  is optional, and is skipped for route origins.
- `MapboxDirectionsService` uses the existing `http` dependency. It calls
  [Mapbox Geocoding v6](https://docs.mapbox.com/api/search/geocoding/) on submit
  (no keystroke/autocomplete requests), then
  [Mapbox Directions v5](https://docs.mapbox.com/api/navigation/directions/)
  with the driving profile and full GeoJSON geometry.
- `MapboxService` owns native map state per screen, preventing navigation and the
  camera thumbnail from overwriting each other's controllers. Route lines are
  drawn below blue origin and orange destination markers. Camera fitting includes
  every route vertex and both original endpoints, with padding and a maximum zoom.
  It refits after the map's available layout size changes, including keyboard and
  route-summary changes.
- Requests are bounded and errors are sanitized; destination edits/disposal
  invalidate stale responses. Native map updates are serialized. GPS, address and
  route results are kept in memory and are not logged or persisted by navigation.

## Use

1. Open **Map Data**, allow location access, and enable device GPS.
2. Enter an address or a place with its city, then choose **Find driving route**.
3. Select the intended result when multiple places match.
4. Inspect the route, total distance, estimated driving time and GPS-fix timestamp.
5. Use **Show entire route** after panning, or **Refresh GPS / route** for a new fix.

This feature is a route preview, not turn-by-turn guidance. Driving time is an
estimate, not a live-traffic guarantee. Native Mapbox maps are supported on
Android and iOS; other platforms show an explanation. An internet connection is
required for geocoding, routing, and uncached map resources. No new Dart packages
are required.

Destination search supports addresses, streets, cities and geographic places.
Geocoding v6 does not include business/POI-name search. It accepts up to 256
characters and 20 words, with commas instead of semicolons. Invalid input is
rejected before GPS or network requests. The API may snap endpoints to the road
network; the markers retain the requested locations, and the polyline shows the
actual returned driving route.

## Automated verification

Tested SDK target: Flutter 3.41.1 / Dart 3.11.0 (matches `pubspec.yaml`).

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
# Check formatting for all repository Dart sources.
dart format --output=none --set-exit-if-changed lib test test_geocoding.dart
```

Tests isolate HTTP, Geolocator, native camera and native-map boundaries. They do
not need a Mapbox token and do not send real destination or location data.
`test_geocoding.dart` is a manual device diagnostic, not an automated unit test.

## Device smoke checklist (requires a configured token)

- Android and iOS: permit location access; search a known nearby address; verify
  both markers, road-following polyline, distance/time and full-route framing.
- Deny permission, retry; permanently deny permission, open app settings, allow
  location and return; turn GPS off/on and verify recovery from location settings.
- Disable networking during search/routing and tile loading; verify messages and
  retries. Test an unknown address and destinations with no connected driving road.
- Select between ambiguous place names; edit input while requests are running;
  clear a successful destination and verify the old route/metrics disappear.
- Pan and restore the full route; test a route with a detour, nearby/coincident
  endpoints and an antimeridian route where supported by the road network.
- Test smaller displays, large text and the software keyboard; controls must
  remain reachable and must not cover Mapbox attribution or the fitted route.
- Repeatedly enter/leave the map and return to the camera; verify preview/capture,
  GPS updates and map state remain independent, with no background timer growth.

Do not treat mocked tests as proof of live native-map rendering. Run this checklist
on target devices before a production release.
