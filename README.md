# GeoTag Camera

A Flutter application that captures photos with automatic geotag information overlay, including GPS coordinates, address, and timestamp.

## Features

- **Camera Integration**: Live camera preview with high-quality image capture
- **Location Services**: Automatic GPS location fetching and address geocoding
- **Image Overlay**: Adds geotag information (coordinates, address, timestamp) as overlay on captured images
- **Save & Share**: Save processed images to device gallery and share with other apps
- **Permission Handling**: Graceful permission requests for camera, location, and storage
- **Map Navigation**: Destination search, driving-route polyline, automatic route framing, distance, and ETA
- **Material 3 UI**: Clean, modern interface following Material Design 3 guidelines

## Requirements

- Flutter SDK (>= 3.11.0)
- Android: API level 21+ (Android 5.0)
- iOS: iOS 11.0+

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

3. Run the app with a public Mapbox access token:
```bash
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_public_token
```

The navigation feature uses the existing `mapbox_maps_flutter` integration.
Mapbox forward geocoding resolves the destination and Mapbox Directions returns
the driving route, distance, and estimated travel time.

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
│   ├── camera_screen.dart    # Camera preview and capture
│   └── preview_screen.dart   # Image preview with overlay
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

### Map navigation

1. Tap the location icon in the top bar or **Map Data** in the bottom bar.
2. Grant location access and enable the device Location Service if prompted.
3. Enter an address or place name and tap the directions button.
4. The map shows the current location, destination, full driving route,
   distance, and estimated travel time.

The navigation screen provides retry or settings actions for denied location
access, disabled GPS, network failures, destinations that cannot be resolved,
and destinations for which no driving route is available.

## Key Dependencies

- `camera: ^1.3.0` - Camera functionality
- `geolocator: ^10.1.0` - GPS location services
- `geocoding: ^3.0.0` - Address geocoding
- `screenshot: ^3.0.0` - Widget to image conversion
- `gallery_saver: ^2.3.3` - Save images to gallery
- `share_plus: ^9.0.0` - Share functionality
- `permission_handler: ^11.3.1` - Permission management
- `flutter_screenutil: ^5.9.3` - Responsive design

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
