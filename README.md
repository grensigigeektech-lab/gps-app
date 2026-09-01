# GeoTag Camera

A Flutter application that captures photos with automatic geotag information overlay, including GPS coordinates, address, and timestamp.

## Features

- **Map navigation**: Open **Map Data** for fresh GPS, destination search/selection, a driving route with origin/destination markers, full-route camera fitting, distance and estimated time. Includes loading, retry and settings recovery. See [Mapbox setup and verification](MAPBOX_SETUP.md).

- **Camera Integration**: Live camera preview with high-quality image capture
- **Location Services**: Automatic GPS location fetching and address geocoding
- **Image Overlay**: Adds geotag information (coordinates, address, timestamp) as overlay on captured images
- **Save & Share**: Save processed images to device gallery and share with other apps
- **Permission Handling**: Graceful permission requests for camera, location, and storage
- **Material 3 UI**: Clean, modern interface following Material Design 3 guidelines

## Requirements

- Flutter 3.41.1 / Dart 3.11.0 or compatible newer SDK
- Android: API level 24+ (Android 7.0; Flutter 3.41 default)
- iOS: iOS 14.0+ (required by the existing Mapbox SDK)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd geotag_camera
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.YOUR_PUBLIC_TOKEN
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
├── main.dart
├── config/mapbox_config.dart
├── routes/app_routes.dart
├── screens/
│   ├── enhanced_camera_screen.dart
│   ├── enhanced_camera_binding.dart
│   ├── map_navigation_screen.dart
│   ├── map_navigation_controller.dart
│   └── map_navigation_binding.dart
├── services/
│   ├── location_service.dart
│   ├── mapbox_location_service.dart
│   ├── mapbox_directions_service.dart
│   ├── mapbox_service.dart
│   ├── camera_service.dart
│   ├── image_service.dart
│   └── compass_service.dart
├── widgets/permission_dialog.dart
└── utils/
```

## Usage

1. **Launch the App**: Open the app and grant required permissions
2. **Camera Preview**: View live camera feed with location status
3. **Capture Photo**: Tap the capture button to take a photo
4. **Preview**: Review the captured image with geotag overlay
5. **Save/Share**: Save to gallery or share with other apps

## Key Dependencies

See `pubspec.yaml` and the committed `pubspec.lock` for exact constraints/versions.

- `mapbox_maps_flutter` — existing native Mapbox map SDK
- `http` — Mapbox geocoding and directions requests
- `get` — existing GetX routes, bindings and reactive state
- `geolocator` / `permission_handler` — GPS and permissions
- `camera` — camera preview and photo capture
- `screenshot`, `image`, `path_provider`, `share_plus` — image processing/sharing
- `flutter_screenutil` — responsive UI support

Navigation adds no new Dart dependencies. See [MAPBOX_SETUP.md](MAPBOX_SETUP.md)
for build-time token configuration, automated checks and the device smoke checklist.

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
