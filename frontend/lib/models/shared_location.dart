import "package:latlong2/latlong.dart";

/// Where a fellow group member was, the last time they told the server.
///
/// The server only ever keeps one of these per person and drops it once it
/// goes stale, so an instance of this class always means "recently", never
/// "at some point in the past".
class SharedLocation {
  final String username;
  final String displayName;
  final String avatarUrl;
  final double latitude;
  final double longitude;

  /// Reported accuracy in metres, when the device supplied one.
  final double? accuracy;

  /// When the position was published, in UTC.
  final DateTime? updatedAt;

  const SharedLocation({
    required this.username,
    required this.displayName,
    this.avatarUrl = "",
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.updatedAt,
  });

  LatLng get point => LatLng(latitude, longitude);

  /// How long ago this position was reported, or null if the server did not
  /// say. Used to caption a marker with "3 min ago" rather than implying the
  /// dot is live to the second.
  Duration? get age {
    final stamp = updatedAt;
    if (stamp == null) return null;
    final elapsed = DateTime.now().toUtc().difference(stamp);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Builds a location from the API payload, or null when the coordinates are
  /// missing or unusable.
  ///
  /// A marker drawn from a half-parsed payload lands somewhere off the coast
  /// of Africa at 0,0, which looks like a real answer and is not one. Refusing
  /// to build the object keeps that off the map entirely.
  static SharedLocation? tryFromJson(Map<String, dynamic> json) {
    final latitude = _toDouble(json["latitude"]);
    final longitude = _toDouble(json["longitude"]);
    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;

    final username = json["username"]?.toString() ?? "";
    final stamp = json["updated_at"]?.toString();

    return SharedLocation(
      username: username,
      displayName: (json["display_name"]?.toString().trim().isNotEmpty ?? false)
          ? json["display_name"].toString().trim()
          : username,
      avatarUrl: json["avatar_url"]?.toString() ?? "",
      latitude: latitude,
      longitude: longitude,
      accuracy: _toDouble(json["accuracy"]),
      updatedAt: stamp == null ? null : DateTime.tryParse(stamp)?.toUtc(),
    );
  }
}
