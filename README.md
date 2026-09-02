# GeoTag Camera

A Flutter application that captures photos with automatic geotag information overlay, including GPS coordinates, address, and timestamp.

## Features

- **Camera Integration**: Live camera preview with high-quality image capture
- **Location Services**: Automatic GPS location fetching and address geocoding
- **Image Overlay**: Adds geotag information (coordinates, address, timestamp) as overlay on captured images
- **Save & Share**: Save processed images to device gallery and share with other apps
- **Permission Handling**: Graceful permission requests for camera, location, and storage
- **Material 3 UI**: Clean, modern interface following Material Design 3 guidelines

## Requirements

- Flutter SDK 3.41.1 / Dart 3.11
- Android: API level 24+ (Android 7.0; Flutter default)
- iOS: iOS 14.0+

## Installation

1. Clone the repository:
```bash
git clone https://github.com/grensigigeektech-lab/gps-app.git
cd gps-app
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Permissions

The app requires the following permissions:

### Android
- `CAMERA` - To capture photos
- `ACCESS_FINE_LOCATION` - To get precise GPS location
- `ACCESS_COARSE_LOCATION` - To get approximate location
- `WRITE_EXTERNAL_STORAGE` - To save images to gallery
- `READ_EXTERNAL_STORAGE` - To access saved images
- `INTERNET` - For geocoding services

### iOS
- `NSCameraUsageDescription` - Camera access for photo capture
- `NSLocationWhenInUseUsageDescription` - Location access for geotagging
- `NSPhotoLibraryAddUsageDescription` - Save photos to library
- `NSPhotoLibraryUsageDescription` - Access photo library

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/
│   ├── enhanced_camera_screen.dart # Camera preview and capture
│   ├── map_navigation_screen.dart  # Destination input and route map
│   └── map_navigation_controller.dart # GetX navigation controller/binding
├── services/
│   ├── camera_service.dart   # Camera operations
│   ├── location_service.dart # GPS and geocoding
│   └── image_service.dart    # Image processing and overlay
├── widgets/
│   └── permission_dialog.dart # Permission request dialog
└── utils/
    └── app_error.dart        # Error handling utilities
```

## Usage

1. **Launch the App**: Open the app and grant required permissions
2. **Camera Preview**: View live camera feed with location status
3. **Capture Photo**: Tap the capture button to take a photo
4. **Preview**: Review the captured image with geotag overlay
5. **Save/Share**: Save to gallery or share with other apps

## Key Dependencies

- `camera: ^0.12.0+1` - Camera functionality
- `geolocator: ^10.1.0` - GPS location services
- `geocoding: ^2.1.1` - Address geocoding
- `screenshot: ^3.0.0` - Widget to image conversion
- `share_plus: ^9.0.0` - Share functionality
- `permission_handler: ^11.3.1` - Permission management
- `flutter_screenutil: ^5.9.3` - Responsive design
- `mapbox_maps_flutter: ^2.23.0` - Existing native map SDK
- `http: ^1.2.0` - Mapbox geocoding and directions
- `get: ^4.6.6` - GetX state management and routes

## Error Handling

The app includes comprehensive error handling for:
- Camera initialization failures
- Location service unavailability
- Permission denials
- Storage issues
- Network connectivity problems

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and feature requests, please open an issue on the GitHub repository.
# gps
# gps-app

## Map navigation

Open **Map Data** from the camera screen. Grant foreground location access,
enter an address or city, tap Search, and choose the intended result. The map
shows a blue current-location marker, a red destination marker, the complete
Mapbox driving-route polyline, and distance/estimated duration. It automatically
fits every route vertex and both endpoints; **Show entire route** fits it again.
**Refresh current location** clears the old route before acquiring a new fix.

This is route planning, not voice-guided turn-by-turn navigation, background
tracking, or automatic rerouting. The driving estimate excludes live traffic.
An address/city search uses Mapbox Geocoding v6; POI/business search is not
provided by that endpoint. Search results require explicit selection to avoid
silently routing to an ambiguous address.

### Runtime configuration

Use Flutter **3.41.1 / Dart 3.11** (matching the repository metadata and lockfile).
The locked Mapbox Maps Flutter 2.23.0 supports Android/iOS, not this project's
web target. iOS requires **14.0+** and a full Xcode installation.

Supply your own **public** Mapbox token at build time:

```sh
flutter pub get --enforce-lockfile
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_PK_TOKEN
flutter build apk --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_PK_TOKEN
```

Do not commit a real token. Never put a secret `sk.`/downloads token into a
Dart define or the mobile binary. The public token must permit your account's
Maps, Geocoding, and Directions usage. Missing/invalid configuration shows an
explicit error instead of making requests with a placeholder. No new Dart
package dependencies were added; `pubspec.lock` is unchanged. The installed
Mapbox plugin already registers its native release repository; duplicate
placeholder-authenticated repositories and placeholder token properties were
removed. Production signing remains a separate release-configuration task.

GPS coordinates and the submitted destination are sent to Mapbox only to
provide map/geocoding/routing functionality. Destination requests run on
explicit search, not each keystroke. Geocoding results and routes stay in memory;
no address, coordinate, access token, or request URL is logged by the new services.
Mapbox's built-in attribution/logo remain visible on the map.

### Architecture and error handling

- `lib/routes/app_routes.dart`: existing GetX route registration; camera's Map
  Data entry opens the navigation screen without replacing the camera flow.
- `lib/screens/map_navigation_controller.dart`: GetX controller/binding for GPS,
  search, selection, routing, loading/error states, retries, settings-return
  recovery, cancellation, and lifecycle cleanup.
- `lib/screens/map_navigation_screen.dart`: destination choices, native Mapbox
  view, route summary, progress, settings actions, and map retry controls.
- `lib/services/navigation_service.dart`: typed results/errors, validated
  coordinates and API payloads, URL-safe geocoding, full GeoJSON directions,
  bounded requests, cancellation, and HTTP client cleanup.
- `lib/services/location_service.dart`: shared permission/service checks and
  fresh GPS acquisition. Navigation skips optional reverse geocoding, never
  substitutes a fixed/last-known coordinate, and rejects stale fixes.
- `lib/services/mapbox_location_service.dart`: camera-compatible adapter to the
  shared foreground GPS implementation (replacing the prior fake fallback and
  unused location-stream stub).
- `lib/services/mapbox_service.dart`: same Mapbox rendering service, now scoped
  per map to prevent the navigation screen and camera thumbnail stealing each
  other's controller. Replaces old route annotations and fits the full route.

Denied/permanently denied permission, disabled GPS, unavailable/timed-out fixes,
invalid/empty/unmatched destinations, network/timeouts, API authentication,
rate limits/server errors, malformed data, no-route/no-road results, and native
map loading/rendering failures all have user-facing feedback. Editing the
input clears obsolete results; request generations prevent late responses from
restoring them. Repeated submissions cannot open overlapping permission dialogs.

### Verification

```sh
dart format --output=none --set-exit-if-changed lib test test_geocoding.dart
flutter analyze --no-pub
flutter test --no-pub --coverage
flutter build apk --debug --no-pub
```

The GitHub Actions workflow repeats formatting, analysis, and tests on PRs to
`main`. Tests use HTTP/platform fakes, not live GPS/Mapbox, and cover GPS failures,
zero coordinates, stale-location rejection, geocoding encoding/selection,
route geometry/metrics, errors/retries, request races/disposal, marker/line
replacement, camera bounds, and navigation widgets. `test_geocoding.dart` is an
existing manual native-plugin diagnostic, not a `flutter_test` suite.

Before release, test on Android and iOS with a real public token: permission
allow/deny/permanent-deny; GPS off and recovery from Settings; airplane mode;
a full-address search with multiple choices; a long/bending route; an unreachable
destination; repeated edits while loading; map reload; back to camera and reopen
Map Data; and compact-screen/keyboard behavior. Automated fakes cannot verify
real map tiles, device GPS accuracy, or native SDK rendering.
