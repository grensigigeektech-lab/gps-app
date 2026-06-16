import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vibration/vibration.dart';

class PermissionDialog extends StatelessWidget {
  final VoidCallback onSettingsPressed;
  final VoidCallback onRetryPressed;

  const PermissionDialog({
    super.key,
    required this.onSettingsPressed,
    required this.onRetryPressed,
  });

  Future<void> _handleButtonPress(VoidCallback onPressed) async {
    await Vibration.vibrate(duration: 50);
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.security,
                color: Colors.red,
                size: 40.w,
              ),
            ),
            
            SizedBox(height: 16.h),
            
            // Title
            Text(
              'Permissions Required',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            
            SizedBox(height: 12.h),
            
            // Description
            Text(
              'This app requires camera and location permissions to work properly. '
              'Camera permission is needed to take photos, and location permission '
              'is used to add geotag information to your images.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            
            SizedBox(height: 24.h),
            
            // Buttons
            Column(
              children: [
                // Settings button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _handleButtonPress(onSettingsPressed),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings, size: 20.w),
                        SizedBox(width: 8.w),
                        Text(
                          'Open Settings',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 12.h),
                
                // Retry button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _handleButtonPress(onRetryPressed),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: BorderSide(color: Colors.blue),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: 20.w),
                        SizedBox(width: 8.w),
                        Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 12.h),
                
                // Cancel button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      await Vibration.vibrate(duration: 50);
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
