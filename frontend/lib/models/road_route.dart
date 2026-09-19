import "package:latlong2/latlong.dart";

class RoadRoute {
  final List<LatLng> geometry;
  final double distanceMeters;
  final double durationSeconds;

  const RoadRoute({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
