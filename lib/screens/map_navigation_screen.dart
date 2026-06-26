import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../models/map_navigation.dart';
import 'map_navigation_controller.dart';

class MapNavigationScreen extends StatefulWidget {
  const MapNavigationScreen({super.key});

  @override
  State<MapNavigationScreen> createState() => _MapNavigationScreenState();
}

class _MapNavigationScreenState extends State<MapNavigationScreen> {
  final _destinationController = TextEditingController();
  final _destinationFocusNode = FocusNode();
  late final MapNavigationController _controller;

  MapboxMap? _map;
  CircleAnnotationManager? _circleManager;
  PolylineAnnotationManager? _polylineManager;
  Worker? _mapStateWorker;
  bool _isSynchronizingMap = false;
  bool _needsAnotherSync = false;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<MapNavigationController>();
    _mapStateWorker = everAll([
      _controller.currentLocation,
      _controller.route,
    ], (_) => _synchronizeMap());
  }

  @override
  void dispose() {
    _mapStateWorker?.dispose();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    _circleManager = await map.annotations.createCircleAnnotationManager();
    _polylineManager = await map.annotations.createPolylineAnnotationManager();
    await _synchronizeMap();
  }

  Future<void> _synchronizeMap() async {
    if (_map == null || _circleManager == null || _polylineManager == null) {
      return;
    }
    if (_isSynchronizingMap) {
      _needsAnotherSync = true;
      return;
    }

    _isSynchronizingMap = true;
    try {
      do {
        _needsAnotherSync = false;
        final map = _map;
        final circleManager = _circleManager;
        final polylineManager = _polylineManager;
        if (map == null || circleManager == null || polylineManager == null) {
          return;
        }

        await circleManager.deleteAll();
        await polylineManager.deleteAll();

        final origin = _controller.currentLocation.value;
        final navigationRoute = _controller.route.value;
        if (origin != null) {
          await circleManager.create(
            _circleOptions(origin, const Color(0xFF1976D2)),
          );
        }
        if (navigationRoute != null) {
          await circleManager.create(
            _circleOptions(
              navigationRoute.destination.coordinate,
              const Color(0xFFE53935),
            ),
          );
          await polylineManager.create(
            PolylineAnnotationOptions(
              geometry: LineString(
                coordinates: navigationRoute.coordinates
                    .map(
                      (coordinate) =>
                          Position(coordinate.longitude, coordinate.latitude),
                    )
                    .toList(growable: false),
              ),
              lineColor: const Color(0xFF1565C0).toARGB32(),
              lineWidth: 6,
              lineBorderColor: Colors.white.toARGB32(),
              lineBorderWidth: 2,
              lineOpacity: 0.9,
            ),
          );
          await _fitRoute(map, navigationRoute.coordinates);
        } else if (origin != null) {
          await map.easeTo(
            CameraOptions(
              center: _point(origin),
              zoom: MapboxConfig.defaultZoom,
            ),
            MapAnimationOptions(
              duration: MapboxConfig.animationDuration.inMilliseconds,
            ),
          );
        }
      } while (_needsAnotherSync);
    } finally {
      _isSynchronizingMap = false;
    }
  }

  CircleAnnotationOptions _circleOptions(
    NavigationCoordinate coordinate,
    Color color,
  ) {
    return CircleAnnotationOptions(
      geometry: _point(coordinate),
      circleColor: color.toARGB32(),
      circleRadius: 9,
      circleStrokeColor: Colors.white.toARGB32(),
      circleStrokeWidth: 3,
    );
  }

  Point _point(NavigationCoordinate coordinate) {
    return Point(
      coordinates: Position(coordinate.longitude, coordinate.latitude),
    );
  }

  Future<void> _fitRoute(
    MapboxMap map,
    List<NavigationCoordinate> coordinates,
  ) async {
    final camera = await map.cameraForCoordinatesPadding(
      coordinates.map(_point).toList(growable: false),
      CameraOptions(
        padding: MbxEdgeInsets(top: 140, left: 48, bottom: 240, right: 48),
      ),
      null,
      16,
      null,
    );
    await map.easeTo(
      camera,
      MapAnimationOptions(
        duration: MapboxConfig.animationDuration.inMilliseconds,
      ),
    );
  }

  Future<void> _submitDestination() async {
    _destinationFocusNode.unfocus();
    await HapticFeedback.lightImpact();
    await _controller.buildRoute(_destinationController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map navigation'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              key: const ValueKey('navigation-map'),
              styleUri: MapboxConfig.streetStyle,
              viewport: CameraViewportState(
                center: Point(coordinates: Position(0, 20)),
                zoom: 1.5,
              ),
              onMapCreated: _onMapCreated,
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: Obx(
                () => _DestinationSearch(
                  controller: _destinationController,
                  focusNode: _destinationFocusNode,
                  isBusy: _controller.isBusy,
                  onSubmitted: _submitDestination,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(top: false, child: Obx(() => _buildStatusCard())),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    switch (_controller.status.value) {
      case MapNavigationStatus.locating:
        return const _ProgressCard(
          icon: Icons.my_location,
          message: 'Finding your current location…',
        );
      case MapNavigationStatus.routing:
        return const _ProgressCard(
          icon: Icons.route,
          message: 'Finding the best route…',
        );
      case MapNavigationStatus.routeReady:
        final route = _controller.route.value;
        if (route != null) {
          return _RouteSummary(route: route);
        }
        return const _ReadyCard();
      case MapNavigationStatus.failure:
        return _ErrorCard(
          message: _controller.errorMessage.value,
          actionLabel: _controller.errorActionLabel.value,
          onAction: _controller.handleErrorAction,
        );
      case MapNavigationStatus.ready:
        return const _ReadyCard();
    }
  }
}

class _DestinationSearch extends StatelessWidget {
  const _DestinationSearch({
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, color: Color(0xFFE53935)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('destination-input'),
                controller: controller,
                focusNode: focusNode,
                enabled: !isBusy,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  hintText: 'Where do you want to go?',
                  hintStyle: TextStyle(color: Colors.black54),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            IconButton.filled(
              key: const ValueKey('destination-submit'),
              tooltip: 'Build route',
              onPressed: isBusy ? null : onSubmitted,
              icon: const Icon(Icons.directions),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _BottomCard(
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard();

  @override
  Widget build(BuildContext context) {
    return const _BottomCard(
      child: Row(
        children: [
          Icon(Icons.my_location, color: Color(0xFF1976D2)),
          SizedBox(width: 12),
          Expanded(
            child: Text('Current location found. Enter a destination above.'),
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});

  final NavigationRoute route;

  @override
  Widget build(BuildContext context) {
    return _BottomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            route.destination.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: route.formattedDistance,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Metric(
                  icon: Icons.schedule,
                  label: 'Estimated time',
                  value: route.formattedDuration,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _LegendDot(color: Color(0xFF1976D2), label: 'Current'),
              SizedBox(width: 16),
              _LegendDot(color: Color(0xFFE53935), label: 'Destination'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.black54)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return _BottomCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (actionLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: onAction, child: Text(actionLabel)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.black87),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
