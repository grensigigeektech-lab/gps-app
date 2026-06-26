import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../models/map_navigation.dart';
import '../services/location_service.dart';
import '../services/map_navigation_service.dart';

enum MapNavigationStatus { locating, ready, routing, routeReady, failure }

class MapNavigationController extends GetxController {
  MapNavigationController({MapNavigationService? navigationService})
    : _navigationService = navigationService ?? MapNavigationService();

  final MapNavigationService _navigationService;

  final status = MapNavigationStatus.locating.obs;
  final currentLocation = Rxn<NavigationCoordinate>();
  final route = Rxn<NavigationRoute>();
  final errorMessage = ''.obs;
  final errorActionLabel = ''.obs;
  final isLocationFailure = false.obs;

  bool get isBusy =>
      status.value == MapNavigationStatus.locating ||
      status.value == MapNavigationStatus.routing;

  @override
  void onInit() {
    super.onInit();
    locateUser();
  }

  Future<void> locateUser() async {
    status.value = MapNavigationStatus.locating;
    errorMessage.value = '';
    errorActionLabel.value = '';
    isLocationFailure.value = false;

    final result = await LocationService.getCurrentLocationResult(
      forceRefresh: true,
    );
    if (result.success) {
      final location = result.info!;
      currentLocation.value = NavigationCoordinate(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      status.value = route.value == null
          ? MapNavigationStatus.ready
          : MapNavigationStatus.routeReady;
      return;
    }

    isLocationFailure.value = true;
    errorMessage.value =
        result.errorMessage ??
        'We could not determine your location. Please try again.';
    if (result.error == LocationError.serviceDisabled) {
      errorActionLabel.value = 'Open location settings';
    } else if (result.error == LocationError.permissionPermanentlyDenied) {
      errorActionLabel.value = 'Open app settings';
    } else {
      errorActionLabel.value = 'Try again';
    }
    status.value = MapNavigationStatus.failure;
  }

  Future<void> buildRoute(String destinationInput) async {
    if (isBusy) return;

    final origin = currentLocation.value;
    if (origin == null) {
      await locateUser();
      return;
    }

    status.value = MapNavigationStatus.routing;
    route.value = null;
    errorMessage.value = '';
    errorActionLabel.value = '';
    isLocationFailure.value = false;

    try {
      final destination = await _navigationService.geocodeDestination(
        destinationInput,
      );
      route.value = await _navigationService.getDrivingRoute(
        origin: origin,
        destination: destination,
      );
      status.value = MapNavigationStatus.routeReady;
    } on MapNavigationException catch (error) {
      errorMessage.value = error.message;
      errorActionLabel.value = 'Try again';
      status.value = MapNavigationStatus.failure;
    } catch (_) {
      errorMessage.value =
          'Something went wrong while building the route. Please try again.';
      errorActionLabel.value = 'Try again';
      status.value = MapNavigationStatus.failure;
    }
  }

  Future<void> handleErrorAction() async {
    if (!isLocationFailure.value) {
      status.value = currentLocation.value == null
          ? MapNavigationStatus.locating
          : MapNavigationStatus.ready;
      errorMessage.value = '';
      errorActionLabel.value = '';
      return;
    }

    final error = errorActionLabel.value;
    if (error == 'Open location settings') {
      await Geolocator.openLocationSettings();
    } else if (error == 'Open app settings') {
      await Geolocator.openAppSettings();
    }
    await locateUser();
  }

  @override
  void onClose() {
    _navigationService.dispose();
    super.onClose();
  }
}
