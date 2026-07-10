import 'package:get/get.dart';

import '../services/navigation_service.dart';
import 'map_navigation_screen.dart';

class MapNavigationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NavigationService>(() => NavigationService());
    Get.lazyPut<MapNavigationController>(
      () => MapNavigationController(Get.find<NavigationService>()),
    );
  }
}
