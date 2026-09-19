import "dart:math" as math;
import "dart:ui" as ui;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:pointer_interceptor/pointer_interceptor.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../utils/theme.dart";
import "windows_google_map.dart";

class DestinationMap extends StatefulWidget {
  final List<Destination> destinations;
  final Destination? selectedDestination;
  final ValueChanged<Destination>? onDestinationSelected;
  final LatLng? currentLocation;
  final ValueChanged<MapController>? onMapCreated;
  final List<LatLng> routePoints;
  final double height;
  final double? zoom;
  final bool compact;

  const DestinationMap({
    super.key,
    required this.destinations,
    this.selectedDestination,
    this.onDestinationSelected,
    this.currentLocation,
    this.onMapCreated,
    this.routePoints = const [],
    this.height = double.infinity,
    this.zoom,
    this.compact = false,
  });

  @override
  State<DestinationMap> createState() => _DestinationMapState();
}

class _DestinationMapState extends State<DestinationMap> {
  late final bool _useFlutterMap;
  late final bool _useWindowsMap;
  late final MapController _mapController;

  List<Destination> get _mappedDestinations => widget.destinations
      .where((destination) => destination.hasCoordinates)
      .toList();

  LatLng get _center {
    final locations = _mappedDestinations
        .map(
          (destination) => LatLng(
            destination.latitude!,
            destination.longitude!,
          ),
        )
        .toList();
    if (locations.isEmpty) return const LatLng(3.8480, 11.5021);
    if (locations.length == 1) return locations.first;

    final latitude = locations.fold<double>(
          0,
          (total, location) => total + location.latitude,
        ) /
        locations.length;
    final longitude = locations.fold<double>(
          0,
          (total, location) => total + location.longitude,
        ) /
        locations.length;
    return LatLng(latitude, longitude);
  }

  double get _initialZoom {
    if (widget.zoom != null) return widget.zoom!;
    if (_mappedDestinations.length <= 1) return 14.5;
    return 7.2;
  }

  @override
  void initState() {
    super.initState();
    _useFlutterMap = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    _useWindowsMap =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant DestinationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentLocation != oldWidget.currentLocation &&
        widget.currentLocation != null) {
      if (_useFlutterMap) {
        _mapController.move(widget.currentLocation!, 15);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mappedDestinations.isEmpty && widget.routePoints.isEmpty) {
      return _bounded(
        _MapMessage(
          title: AppLocalizations.of(context).noMappedPlaces,
          message: AppLocalizations.of(context).noMappedPlacesMessage,
          icon: Icons.location_off_outlined,
        ),
      );
    }

    final mapContent = _useFlutterMap
        ? _buildGoogleMap()
        : _useWindowsMap
            ? _buildWindowsGoogleMap()
            : _buildVectorMap();
    return _bounded(mapContent);
  }

  Widget _buildGoogleMap() {
    widget.onMapCreated?.call(_mapController);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: widget.currentLocation ??
              (widget.selectedDestination?.hasCoordinates == true
                  ? LatLng(
                      widget.selectedDestination!.latitude!,
                      widget.selectedDestination!.longitude!,
                    )
                  : _center),
          initialZoom: widget.currentLocation != null || widget.selectedDestination != null
              ? (widget.zoom ?? 14.5)
              : _initialZoom,
          minZoom: 3,
          maxZoom: 20,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: "com.globetrotter.app",
          ),
          MarkerLayer(
            markers: _markers,
          ),
          if (widget.routePoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.routePoints,
                  strokeWidth: 5.0,
                  color: AppTheme.secondary,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWindowsGoogleMap() {
    return WindowsGoogleMap(
      destinations: _mappedDestinations,
      selectedDestination: widget.selectedDestination,
      currentLocation: widget.currentLocation,
      routePoints: widget.routePoints,
      onDestinationSelected: widget.onDestinationSelected,
    );
  }

  Widget _buildVectorMap() {
    return _InteractiveVectorMap(
      destinations: _mappedDestinations,
      selectedDestination: widget.selectedDestination,
      currentLocation: widget.currentLocation,
      routePoints: widget.routePoints,
      onDestinationSelected: widget.onDestinationSelected,
      compact: widget.compact,
    );
  }

  List<Marker> get _markers {
    final markers = <Marker>[];
    if (widget.currentLocation != null) {
      markers.add(
        Marker(
          point: widget.currentLocation!,
          width: 24,
          height: 24,
          child: const Icon(
            Icons.my_location_rounded,
            color: Colors.blue,
            size: 24,
          ),
        ),
      );
    }
    for (final destination in _mappedDestinations) {
      final selected = destination.id == widget.selectedDestination?.id;
      markers.add(
        Marker(
          point: LatLng(destination.latitude!, destination.longitude!),
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => widget.onDestinationSelected?.call(destination),
            child: Icon(
              Icons.location_on_rounded,
              color: selected ? AppTheme.secondary : AppTheme.primary,
              size: 30,
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _bounded(Widget child) => widget.height == double.infinity
      ? child
      : SizedBox(height: widget.height, child: child);
}

class _InteractiveVectorMap extends StatefulWidget {
  final List<Destination> destinations;
  final Destination? selectedDestination;
  final LatLng? currentLocation;
  final List<LatLng> routePoints;
  final ValueChanged<Destination>? onDestinationSelected;
  final bool compact;

  const _InteractiveVectorMap({
    required this.destinations,
    this.selectedDestination,
    this.currentLocation,
    this.routePoints = const [],
    this.onDestinationSelected,
    this.compact = false,
  });

  @override
  State<_InteractiveVectorMap> createState() => _InteractiveVectorMapState();
}

class _InteractiveVectorMapState extends State<_InteractiveVectorMap> {
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;

  void _zoomIn() {
    setState(() {
      _zoomLevel = math.min(_zoomLevel * 1.25, 3.5);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = math.max(_zoomLevel / 1.25, 0.75);
    });
  }

  void _resetView() {
    setState(() {
      _zoomLevel = 1.0;
      _panOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2EC),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.primarySoft.withValues(alpha: 0.8)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _panOffset += details.delta;
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              child: CustomPaint(
                painter: _CameroonMapPainter(
                  destinations: widget.destinations,
                  selectedDestination: widget.selectedDestination,
                  currentLocation: widget.currentLocation,
                  routePoints: widget.routePoints,
                  zoomLevel: _zoomLevel,
                  panOffset: _panOffset,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              if (width <= 0 || height <= 0) return const SizedBox();

              return Stack(
                children: [
                  for (final dest in widget.destinations)
                    _buildPinWidget(dest, width, height),
                  if (widget.currentLocation != null)
                    _buildCurrentLocationPinWidget(width, height),
                ],
              );
            },
          ),
          Positioned(
            bottom: widget.compact ? 12 : 16,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _mapControlButton(
                  icon: Icons.add,
                  onPressed: _zoomIn,
                ),
                const SizedBox(height: 6),
                _mapControlButton(
                  icon: Icons.remove,
                  onPressed: _zoomOut,
                ),
                const SizedBox(height: 6),
                _mapControlButton(
                  icon: Icons.center_focus_strong_rounded,
                  onPressed: _resetView,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 18, color: AppTheme.primaryDark),
        ),
      ),
    );
  }

  Widget _buildPinWidget(Destination dest, double mapWidth, double mapHeight) {
    const minLat = 1.8;
    const maxLat = 12.8;
    const minLng = 8.5;
    const maxLng = 16.2;

    final lat = dest.latitude!;
    final lng = dest.longitude!;

    final normalizedX = (lng - minLng) / (maxLng - minLng);
    final normalizedY = 1.0 - ((lat - minLat) / (maxLat - minLat));

    final centerX = mapWidth / 2 + _panOffset.dx;
    final centerY = mapHeight / 2 + _panOffset.dy;

    final basePos = Offset(
      (normalizedX - 0.5) * mapWidth * 0.85,
      (normalizedY - 0.5) * mapHeight * 0.85,
    );

    final posX = centerX + basePos.dx * _zoomLevel;
    final posY = centerY + basePos.dy * _zoomLevel;

    final isSelected = dest.id == widget.selectedDestination?.id;

    return Positioned(
      left: posX - 18,
      top: posY - 36,
      child: GestureDetector(
        onTap: () => widget.onDestinationSelected?.call(dest),
        child: AnimatedScale(
          scale: isSelected ? 1.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.secondary : AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  dest.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.location_on_rounded,
                color: isSelected ? AppTheme.secondary : AppTheme.primary,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentLocationPinWidget(double mapWidth, double mapHeight) {
    const minLat = 1.8;
    const maxLat = 12.8;
    const minLng = 8.5;
    const maxLng = 16.2;

    final lat = widget.currentLocation!.latitude;
    final lng = widget.currentLocation!.longitude;

    final normalizedX = (lng - minLng) / (maxLng - minLng);
    final normalizedY = 1.0 - ((lat - minLat) / (maxLat - minLat));

    final centerX = mapWidth / 2 + _panOffset.dx;
    final centerY = mapHeight / 2 + _panOffset.dy;

    final basePos = Offset(
      (normalizedX - 0.5) * mapWidth * 0.85,
      (normalizedY - 0.5) * mapHeight * 0.85,
    );

    final posX = centerX + basePos.dx * _zoomLevel;
    final posY = centerY + basePos.dy * _zoomLevel;

    return Positioned(
      left: posX - 14,
      top: posY - 14,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.25),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameroonMapPainter extends CustomPainter {
  final List<Destination> destinations;
  final Destination? selectedDestination;
  final LatLng? currentLocation;
  final List<LatLng> routePoints;
  final double zoomLevel;
  final Offset panOffset;

  _CameroonMapPainter({
    required this.destinations,
    required this.selectedDestination,
    required this.currentLocation,
    required this.routePoints,
    required this.zoomLevel,
    required this.panOffset,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final backgroundPaint = ui.Paint()..color = const Color(0xFFE3EFE9);
    canvas.drawRect(ui.Offset.zero & size, backgroundPaint);

    final gridPaint = ui.Paint()
      ..color = const Color(0xFFC7DCD1)
      ..strokeWidth = 1.0;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y), gridPaint);
    }

    final oceanPaint = ui.Paint()..color = const Color(0xFFD0E6FB);
    final oceanPath = ui.Path()
      ..moveTo(0, size.height * 0.5)
      ..cubicTo(
        size.width * 0.15,
        size.height * 0.6,
        size.width * 0.25,
        size.height * 0.85,
        0,
        size.height,
      )
      ..close();
    canvas.drawPath(oceanPath, oceanPaint);

    if (routePoints.length >= 2) {
      final routePaint = ui.Paint()
        ..color = AppTheme.secondary
        ..strokeWidth = 4.0 * zoomLevel
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;

      final path = ui.Path();
      bool first = true;

      const minLat = 1.8;
      const maxLat = 12.8;
      const minLng = 8.5;
      const maxLng = 16.2;

      for (final point in routePoints) {
        final normalizedX = (point.longitude - minLng) / (maxLng - minLng);
        final normalizedY = 1.0 - ((point.latitude - minLat) / (maxLat - minLat));

        final centerX = size.width / 2 + panOffset.dx;
        final centerY = size.height / 2 + panOffset.dy;

        final basePos = ui.Offset(
          (normalizedX - 0.5) * size.width * 0.85,
          (normalizedY - 0.5) * size.height * 0.85,
        );

        final posX = centerX + basePos.dx * zoomLevel;
        final posY = centerY + basePos.dy * zoomLevel;

        if (first) {
          path.moveTo(posX, posY);
          first = false;
        } else {
          path.lineTo(posX, posY);
        }
      }
      canvas.drawPath(path, routePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CameroonMapPainter oldDelegate) {
    return oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.selectedDestination != selectedDestination ||
        oldDelegate.destinations != destinations ||
        oldDelegate.routePoints != routePoints;
  }
}

class _MapMessage extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _MapMessage({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primarySoft,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primary, size: 32),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Keeps Flutter overlays clickable when the map uses an HtmlElementView on
/// web. On mobile PointerInterceptor is a no-op and preserves the same layout.
Widget interceptMapOverlay(Widget child) =>
    kIsWeb ? PointerInterceptor(child: child) : child;
