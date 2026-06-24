import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import 'map_navigation_controller.dart';

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapWidget(
                key: const ValueKey('navigation_map'),
                styleUri: MapboxConfig.streetStyle,
                cameraOptions: CameraOptions(
                  center: Point(coordinates: Position(0, 0)),
                  zoom: 2,
                ),
                onMapCreated: controller.onMapCreated,
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _DestinationCard(controller: controller),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Obx(() => _StatusCard(controller: controller)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.controller});

  final MapNavigationController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xff1e1e1e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: Get.back,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('destination_input'),
                controller: controller.destinationController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => controller.createRoute(),
                decoration: const InputDecoration(
                  hintText: 'Where do you want to go?',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Obx(
              () => controller.isBusy
                  ? const SizedBox(
                      width: 42,
                      height: 42,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : IconButton.filled(
                      key: const ValueKey('route_button'),
                      tooltip: 'Build route',
                      onPressed: controller.createRoute,
                      icon: const Icon(Icons.directions),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final MapNavigationController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.viewState.value;
    final route = controller.route.value;
    if (state == NavigationViewState.ready && route == null) {
      return _card(
        child: const Row(
          children: [
            Icon(Icons.my_location, color: Colors.blueAccent),
            SizedBox(width: 12),
            Expanded(
                child: Text('Current location found. Enter a destination.')),
          ],
        ),
      );
    }
    if (state == NavigationViewState.locating ||
        state == NavigationViewState.loadingRoute) {
      return _card(
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Text(
              state == NavigationViewState.locating
                  ? 'Finding your current location…'
                  : 'Finding the best driving route…',
            ),
          ],
        ),
      );
    }
    if (state == NavigationViewState.error) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text(
                  'Navigation unavailable',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(controller.errorMessage.value),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: controller.currentLocation.value == null
                      ? controller.locateUser
                      : controller.createRoute,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
                if (controller.isSettingsActionAvailable.value)
                  TextButton.icon(
                    onPressed: controller.openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open settings'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (route != null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.destination.value?.name ?? 'Destination',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.route,
                    label: 'Distance',
                    value: route.formattedDistance,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.schedule,
                    label: 'Estimated time',
                    value: route.formattedDuration,
                  ),
                ),
                IconButton(
                  tooltip: 'Clear route',
                  onPressed: controller.clearRoute,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _card({required Widget child}) {
    return Material(
      color: const Color(0xee1e1e1e),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
