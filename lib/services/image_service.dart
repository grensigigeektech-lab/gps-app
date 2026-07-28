import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../services/location_service.dart';

class ImageService {
  static final ScreenshotController _screenshotController =
      ScreenshotController();

  static ScreenshotController get screenshotController => _screenshotController;

  static Future<String?> saveImageWithOverlay(
    String originalImagePath,
    LocationInfo locationInfo,
    GlobalKey overlayKey,
  ) async {
    try {
      // 1. Capture the overlay as an image
      final overlayBytes = await _screenshotController.captureFromWidget(
        _buildOverlayWidget(locationInfo),
        context: null,
        pixelRatio: 2.0,
      );

      // 2. Load the original image
      File originalFile = File(originalImagePath);
      if (!originalFile.existsSync()) {
        throw Exception('Original image file not found');
      }

      Uint8List originalBytes = await originalFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(originalBytes);

      if (originalImage == null) {
        throw Exception('Failed to decode original image');
      }

      // 3. Load the overlay image
      img.Image? overlayImage = img.decodeImage(overlayBytes);
      if (overlayImage == null) {
        throw Exception('Failed to decode overlay image');
      }

      // 4. Resize overlay to match original image width
      int overlayHeight = (originalImage.height * 0.25)
          .round(); // 25% of image height
      img.Image resizedOverlay = img.copyResize(
        overlayImage,
        width: originalImage.width,
        height: overlayHeight,
        interpolation: img.Interpolation.average,
      );

      // 5. Create a composite image
      img.Image compositeImage = img.Image(
        width: originalImage.width,
        height: originalImage.height,
      );

      // Copy original image
      img.compositeImage(compositeImage, originalImage);

      // Add overlay at the bottom
      img.compositeImage(
        compositeImage,
        resizedOverlay,
        dstX: 0,
        dstY: originalImage.height - overlayHeight,
      );

      // 6. Save the composite image
      String fileName = 'geotag_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final directory = await getTemporaryDirectory();
      String tempPath = '${directory.path}/$fileName';

      File tempFile = File(tempPath);
      await tempFile.writeAsBytes(img.encodeJpg(compositeImage, quality: 95));

      return tempPath;
    } catch (e) {
      throw Exception('Failed to save image with overlay: $e');
    }
  }

  static Future<String?> saveToGallery(String imagePath) async {
    try {
      // For now, just return the original path since gallery saving
      // requires platform-specific implementation
      // The user can manually save the image from the share dialog
      return imagePath;
    } catch (e) {
      throw Exception('Failed to save to gallery: $e');
    }
  }

  static Future<void> shareImage(String imagePath) async {
    try {
      await Share.shareXFiles([
        XFile(imagePath),
      ], text: 'Photo captured with GeoTag Camera');
    } catch (e) {
      throw Exception('Failed to share image: $e');
    }
  }

  static Widget _buildOverlayWidget(LocationInfo locationInfo) {
    return Container(
      width: 400,
      height: 100,
      color: Colors.black.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    locationInfo.coordinates,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            if (locationInfo.address != null)
              Row(
                children: [
                  Icon(Icons.place, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      locationInfo.address!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (locationInfo.address != null) SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  DateFormat(
                    'yyyy-MM-dd HH:mm:ss',
                  ).format(locationInfo.timestamp),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Future<String?> createOverlayPreview(
    LocationInfo locationInfo,
    double width,
    double height,
  ) async {
    try {
      final overlayBytes = await _screenshotController.captureFromWidget(
        Container(
          width: width,
          height: height * 0.25,
          color: Colors.black.withValues(alpha: 0.8),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locationInfo.coordinates,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                if (locationInfo.address != null)
                  Row(
                    children: [
                      Icon(Icons.place, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          locationInfo.address!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                if (locationInfo.address != null) SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      DateFormat(
                        'yyyy-MM-dd HH:mm:ss',
                      ).format(locationInfo.timestamp),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        context: null,
        pixelRatio: 2.0,
      );

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      String tempPath =
          '${directory.path}/overlay_preview_${DateTime.now().millisecondsSinceEpoch}.png';

      File tempFile = File(tempPath);
      await tempFile.writeAsBytes(overlayBytes);

      return tempPath;
    } catch (e) {
      debugPrint('Failed to create overlay preview: $e');
      return null;
    }
  }

  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      List<FileSystemEntity> files = tempDir.listSync();

      for (FileSystemEntity file in files) {
        if (file is File &&
            (file.path.contains('geotag_') ||
                file.path.contains('overlay_preview_'))) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Failed to delete temp file ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup temp files: $e');
    }
  }
}
