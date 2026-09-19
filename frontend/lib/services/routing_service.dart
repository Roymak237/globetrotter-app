import "dart:convert";

import "package:latlong2/latlong.dart";
import "package:http/http.dart" as http;

import "../models/road_route.dart";

class RoutingService {
  static const _host = "router.project-osrm.org";
  static const _routePath = "/route/v1/driving";
  static const _timeout = Duration(seconds: 15);

  Future<RoadRoute> fetchDrivingRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      throw Exception("At least two mapped stops are required.");
    }

    final coordinates = waypoints
        .map((point) => "${point.longitude},${point.latitude}")
        .join(";");
    final uri = Uri.https(
      _host,
      "$_routePath/$coordinates",
      const {
        "overview": "full",
        "geometries": "geojson",
        "steps": "false",
      },
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception("The road route service is unavailable.");
    }

    final payload = json.decode(response.body);
    if (payload is! Map<String, dynamic> || payload["code"] != "Ok") {
      throw Exception("No road route was found for these stops.");
    }

    final routes = payload["routes"];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw Exception("No road route was found for these stops.");
    }

    final route = Map<String, dynamic>.from(routes.first as Map);
    final geometry = _parseGeometry(route["geometry"]);
    if (geometry.length < 2) {
      throw Exception("The road route had no usable geometry.");
    }

    return RoadRoute(
      geometry: geometry,
      distanceMeters: _number(route["distance"]),
      durationSeconds: _number(route["duration"]),
    );
  }

  List<LatLng> _parseGeometry(Object? value) {
    if (value is! Map || value["coordinates"] is! List) return const [];

    final coordinates = value["coordinates"] as List;
    return coordinates
        .whereType<List>()
        .where((pair) => pair.length >= 2)
        .map(
          (pair) => LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          ),
        )
        .toList();
  }

  double _number(Object? value) => value is num ? value.toDouble() : 0;
}
