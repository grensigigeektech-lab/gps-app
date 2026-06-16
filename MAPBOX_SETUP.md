# Mapbox Integration Setup Guide

## 🚀 Quick Setup

### 1. Get Your Mapbox API Key
1. Go to [Mapbox Account](https://account.mapbox.com/access-tokens/)
2. Sign up or log in
3. Create a new access token or use your default public token
4. Copy the token (starts with `pk.`)

### 2. Configure API Key in Your App

#### Option A: Using Config File (Recommended)
Edit `lib/config/mapbox_config.dart`:
```dart
static const String accessToken = 'pk.your_actual_token_here';
```

#### Option B: Using Android Manifest
Edit `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.mapbox.token"
    android:value="pk.your_actual_token_here" />
```

#### Option C: Using iOS Info.plist
Edit `ios/Runner/Info.plist`:
```xml
<key>MGLMapboxAccessToken</key>
<string>pk.your_actual_token_here</string>
```

### 3. Run the App
```bash
flutter pub get
flutter run
```

## 🛠️ Features Implemented

### ✅ Core Map Functionality
- **Interactive Mapbox Map** with gesture support
- **Real-time Location Tracking** with GPS
- **Live Compass** with device sensors
- **Multiple Map Styles** (Street, Satellite, Dark, Light)
- **Zoom Controls** with smooth animations
- **Marker Placement** at current location

### ✅ Beautiful UI/UX
- **Location Overlay** (Top Left): Shows coordinates, address, timestamp
- **Compass Widget** (Top Right): Real-time heading with cardinal directions
- **Map Style Selector** (Bottom Left): Quick style switching
- **Zoom Controls** (Bottom Right): Zoom in/out and marker tools
- **Center Location Button** (Bottom Center): Quick navigation to current position

### ✅ Advanced Features
- **Permission Handling** with user-friendly prompts
- **Smooth Animations** and transitions
- **Haptic Feedback** for better UX
- **Error Handling** and fallbacks
- **Responsive Design** for different screen sizes

## 🎯 Navigation

Access the map from the home screen:
1. Launch the app
2. Tap the **"Map"** button (middle option)
3. Grant location permissions when prompted
4. Enjoy the interactive map experience!

## 🔧 Troubleshooting

### Build Issues
If you encounter build errors related to Mapbox:

1. **Clean the project:**
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Check your API key** - Make sure it's a valid public token starting with `pk.`

3. **Android Gradle Issues:**
   - Update Android Studio
   - Run `flutter doctor --android-licenses`

4. **iOS Build Issues:**
   - Update Xcode
   - Clean build folder in Xcode

### Runtime Issues

**"Map not loading":**
- Check internet connection
- Verify API key is valid
- Check location permissions

**"Compass not working":**
- Ensure device has magnetometer
- Check sensor permissions
- Calibrate device compass

**"Location not updating":**
- Enable location services
- Grant precise location permission
- Check GPS signal strength

## 🎨 Customization

### Change Default Map Style
Edit `lib/config/mapbox_config.dart`:
```dart
static const String defaultStyle = 'mapbox://styles/mapbox/dark-v11';
```

### Customize UI Colors
Edit the color schemes in `lib/screens/map_screen/map_screen.dart`

### Add New Map Styles
```dart
static const String customStyle = 'mapbox://styles/your_username/your_style_id';
```

## 📱 Permissions Required

- **Location**: GPS coordinates and address lookup
- **Sensors**: Compass functionality
- **Internet**: Map tiles and API calls
- **Storage**: Cache map data

## 🚀 Performance Tips

1. **Use appropriate zoom levels** for your use case
2. **Limit marker count** for better performance
3. **Cache location data** when possible
4. **Optimize update intervals** for location and compass

## 📞 Support

If you encounter issues:
1. Check this guide first
2. Verify API key configuration
3. Review console logs for specific errors
4. Test with a different device if possible

Enjoy your beautiful Mapbox-powered map application! 🗺️✨
