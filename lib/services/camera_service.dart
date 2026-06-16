import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  static CameraController? _controller;
  static List<CameraDescription> _cameras = [];
  static int _currentCameraIndex = 0;

  static Future<void> initialize() async {
    try {
      // Request camera permission
      await Permission.camera.request();
      
      // Get available cameras
      _cameras = await availableCameras();
      
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Initialize the first camera (usually back camera)
      await _initializeCamera(_currentCameraIndex);
    } catch (e) {
      throw Exception('Failed to initialize camera: $e');
    }
  }

  static Future<void> _initializeCamera(int cameraIndex) async {
    if (cameraIndex >= _cameras.length) {
      throw Exception('Camera index out of range');
    }

    // Dispose existing controller
    await _controller?.dispose();

    // Create new controller
    _controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _controller!.initialize();
  }

  static CameraController? get controller => _controller;

  static List<CameraDescription> get cameras => _cameras;

  static int get currentCameraIndex => _currentCameraIndex;

  static bool get isInitialized => _controller?.value.isInitialized ?? false;

  static Future<XFile?> capturePhoto() async {
    if (!isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      return await _controller!.takePicture();
    } catch (e) {
      throw Exception('Failed to capture photo: $e');
    }
  }

  static Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      return; // No other camera to switch to
    }

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initializeCamera(_currentCameraIndex);
  }

  static Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  static Future<bool> hasCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  static Future<bool> requestCameraPermission() async {
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  static String getCameraDescription() {
    if (_cameras.isEmpty) return 'No Camera';
    
    final camera = _cameras[_currentCameraIndex];
    final lensDirection = camera.lensDirection;
    
    if (lensDirection == CameraLensDirection.back) {
      return 'Back Camera';
    } else if (lensDirection == CameraLensDirection.front) {
      return 'Front Camera';
    } else {
      return 'External Camera';
    }
  }
}
