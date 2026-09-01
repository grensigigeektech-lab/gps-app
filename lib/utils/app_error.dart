class AppError {
  final String message;
  final String? details;
  final AppErrorType type;

  AppError({required this.message, this.details, required this.type});

  @override
  String toString() {
    return 'AppError(message: $message, type: $type, details: $details)';
  }
}

enum AppErrorType { camera, location, storage, network, permission, unknown }

class AppErrorHandler {
  static AppError handleError(dynamic error) {
    if (error is AppError) return error;

    String message = 'An unknown error occurred';
    AppErrorType type = AppErrorType.unknown;
    String? details = error.toString();

    if (error.toString().toLowerCase().contains('camera')) {
      message = 'Camera error occurred';
      type = AppErrorType.camera;
    } else if (error.toString().toLowerCase().contains('location')) {
      message = 'Location error occurred';
      type = AppErrorType.location;
    } else if (error.toString().toLowerCase().contains('storage')) {
      message = 'Storage error occurred';
      type = AppErrorType.storage;
    } else if (error.toString().toLowerCase().contains('permission')) {
      message = 'Permission error occurred';
      type = AppErrorType.permission;
    } else if (error.toString().toLowerCase().contains('network')) {
      message = 'Network error occurred';
      type = AppErrorType.network;
    }

    return AppError(message: message, details: details, type: type);
  }

  static String getErrorMessage(AppError error) {
    switch (error.type) {
      case AppErrorType.camera:
        return 'Unable to access camera. Please check permissions and try again.';
      case AppErrorType.location:
        return 'Unable to get location. Please enable GPS and try again.';
      case AppErrorType.storage:
        return 'Unable to save photo. Please check storage permissions.';
      case AppErrorType.permission:
        return 'Required permissions are missing. Please grant permissions in settings.';
      case AppErrorType.network:
        return 'Network error. Please check your internet connection.';
      case AppErrorType.unknown:
        return error.message;
    }
  }
}
