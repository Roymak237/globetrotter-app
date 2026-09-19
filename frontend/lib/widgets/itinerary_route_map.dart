import "package:flutter/material.dart";
import "package:latlong2/latlong.dart";

import "../models/destination.dart";
import "../models/road_route.dart";
import "../services/api_service.dart";
import "../services/routing_service.dart";
import "../utils/theme.dart";
import "destination_map.dart";

class ItineraryRouteMap extends StatefulWidget {
  final List<String> destinationNames;
  final List<Destination>? destinations;
  final double height;

  const ItineraryRouteMap({
    super.key,
    required this.destinationNames,
    this.destinations,
    this.height = 250,
  });

  @override
  State<ItineraryRouteMap> createState() => _ItineraryRouteMapState();
}

class _ItineraryRouteMapState extends State<ItineraryRouteMap> {
  final _routingService = RoutingService();
  Future<List<Destination>>? _destinationsFuture;
  Future<RoadRoute>? _roadRouteFuture;
  String _routeKey = "";

  @override
  void initState() {
    super.initState();
    _routeKey = _routeIdentity(widget.destinationNames);
  }

  @override
  void didUpdateWidget(covariant ItineraryRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _routeIdentity(widget.destinationNames);
    if (nextKey == _routeKey && oldWidget.destinations == widget.destinations) {
      return;
    }

    _routeKey = nextKey;
    _destinationsFuture = null;
    _roadRouteFuture = null;
  }

  String _routeIdentity(List<String> names) => names.join("\u0000");

  @override
  Widget build(BuildContext context) {
    if (widget.destinations != null) {
      return _buildForDestinations(
        context,
        _orderedDestinations(widget.destinations!),
      );
    }

    _destinationsFuture ??= ApiService().searchDestinations();
    return FutureBuilder<List<Destination>>(
      future: _destinationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _MapMessage(
            height: widget.height,
            icon: Icons.route_rounded,
            message: "Opening the destination guide…",
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return _MapMessage(
            height: widget.height,
            icon: Icons.map_outlined,
            message: "The route map is unavailable right now.",
          );
        }
        return _buildForDestinations(
          context,
          _orderedDestinations(snapshot.data ?? const <Destination>[]),
        );
      },
    );
  }

  List<Destination> _orderedDestinations(List<Destination> available) {
    final byName = <String, Destination>{
      for (final destination in available) destination.name: destination,
    };
    return widget.destinationNames
        .map((name) => byName[name])
        .whereType<Destination>()
        .where((destination) => destination.hasCoordinates)
        .toList();
  }

  Widget _buildForDestinations(
    BuildContext context,
    List<Destination> route,
  ) {
    final waypoints = route
        .map(
          (destination) => LatLng(
            destination.latitude!,
            destination.longitude!,
          ),
        )
        .toList();

    if (waypoints.length < 2) {
      return _buildCard(
        context,
        route: route,
        routePoints: waypoints,
        roadRoute: null,
        isLoading: false,
        isFallback: false,
      );
    }

    _roadRouteFuture ??= _routingService.fetchDrivingRoute(waypoints);
    return FutureBuilder<RoadRoute>(
      future: _roadRouteFuture,
      builder: (context, snapshot) {
        final roadRoute = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final isFallback = snapshot.hasError;

        return _buildCard(
          context,
          route: route,
          routePoints: roadRoute?.geometry ?? waypoints,
          roadRoute: roadRoute,
          isLoading: isLoading,
          isFallback: isFallback,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required List<Destination> route,
    required List<LatLng> routePoints,
    required RoadRoute? roadRoute,
    required bool isLoading,
    required bool isFallback,
  }) {
    final hasRoadRoute = roadRoute != null;
    final canRoute = routePoints.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.alt_route_rounded,
                color: AppTheme.primary,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "ROAD PATHWAY",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.secondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
              Text(
                "${route.length} stop${route.length == 1 ? "" : "s"}",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            route.length < 2
                ? "Add another mapped stop to draw the route between places."
                : hasRoadRoute
                    ? "The line follows drivable roads in your selected order."
                    : "The line follows the order of your selected stops.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
          ),
          if (canRoute) ...[
            const SizedBox(height: 10),
            _RouteStatus(
              roadRoute: roadRoute,
              isLoading: isLoading,
              isFallback: isFallback,
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: DestinationMap(
              destinations: route,
              routePoints: routePoints,
              height: widget.height,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStatus extends StatelessWidget {
  final RoadRoute? roadRoute;
  final bool isLoading;
  final bool isFallback;

  const _RouteStatus({
    required this.roadRoute,
    required this.isLoading,
    required this.isFallback,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String message;

    if (isLoading) {
      color = AppTheme.primary;
      icon = Icons.sync_rounded;
      message = "Finding a road route…";
    } else if (roadRoute != null) {
      color = AppTheme.primaryDark;
      icon = Icons.check_circle_outline_rounded;
      message =
          "${_formatDistance(roadRoute!.distanceMeters)}  •  ${_formatDuration(roadRoute!.durationSeconds)} driving";
    } else if (isFallback) {
      color = AppTheme.textSecondary;
      icon = Icons.info_outline_rounded;
      message = "Road routing is unavailable; showing the direct pathway.";
    } else {
      color = AppTheme.textSecondary;
      icon = Icons.route_outlined;
      message = "Select two or more mapped stops to calculate roads.";
    }

    return Row(
      children: [
        if (isLoading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, color: color, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return "${meters.round()} m";
  final kilometers = meters / 1000;
  if (kilometers < 100) return "${kilometers.toStringAsFixed(1)} km";
  return "${kilometers.round()} km";
}

String _formatDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return "~$minutes min";
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) return "~${hours}h";
  return "~${hours}h ${remainingMinutes}m";
}

class _MapMessage extends StatelessWidget {
  final double height;
  final IconData icon;
  final String message;
  final bool loading;

  const _MapMessage({
    required this.height,
    required this.icon,
    required this.message,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height + 70,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.primary, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
