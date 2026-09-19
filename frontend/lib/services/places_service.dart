import "dart:convert";

import "package:globetrotter/models/place_extras.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;

/// Everything surrounding a destination rather than the destination itself:
/// what else is close by, what services exist on the ground, and what
/// travellers thought of it.
///
/// Amenity lookups reach OpenStreetMap through the backend, which caches them.
/// That upstream is a free shared service, so it can be slow or briefly
/// unavailable; [fetchAmenities] therefore treats a failure as "nothing to
/// show" rather than an error, because a detail screen should still render.
class PlacesService {
  final String _base =
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}";

  Map<String, String> _headers(String? token, {bool json = false}) => {
        if (token != null) "Authorization": "Bearer $token",
        if (json) "Content-Type": "application/json",
      };

  Never _fail(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body["error"] != null) {
        throw Exception(body["error"].toString());
      }
    } on FormatException {
      // Body was not JSON; a proxy may have returned an HTML error page.
    }
    throw Exception(fallback);
  }

  /// Other catalogue destinations within [radiusKm], nearest first.
  Future<List<NearbyPlace>> fetchNearby(String destinationId,
      {double radiusKm = 5}) async {
    final uri = Uri.parse("$_base/destinations/$destinationId/nearby")
        .replace(queryParameters: {"radius_km": radiusKm.toString()});

    final response = await http.get(uri).timeout(AppConstants.apiTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(NearbyPlace.fromJson)
          .toList();
    }
    _fail(response, "Could not load nearby places");
  }

  /// Real-world services around a destination, grouped by category.
  ///
  /// Returns an empty list when the lookup fails or the destination has no
  /// coordinates, so callers can render "nothing found" without special-casing.
  Future<List<AmenityGroup>> fetchAmenities(String destinationId,
      {String? category}) async {
    final uri = Uri.parse("$_base/destinations/$destinationId/amenities")
        .replace(
            queryParameters: category == null ? null : {"category": category});

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final groups = body["categories"] as List<dynamic>? ?? const [];
      return groups
          .whereType<Map<String, dynamic>>()
          .map(AmenityGroup.fromJson)
          .where((group) => group.items.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The aggregate rating, plus the viewer's own when [token] is supplied.
  Future<RatingSummary> fetchRating(String destinationId,
      {String? token}) async {
    final response = await http
        .get(
          Uri.parse("$_base/destinations/$destinationId/rating"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return RatingSummary.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not load ratings");
  }

  Future<RatingSummary> setRating({
    required String token,
    required String destinationId,
    required int stars,
  }) async {
    final response = await http
        .put(
          Uri.parse("$_base/destinations/$destinationId/rating"),
          headers: _headers(token, json: true),
          body: jsonEncode({"stars": stars}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return RatingSummary.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not save your rating");
  }

  Future<RatingSummary> clearRating({
    required String token,
    required String destinationId,
  }) async {
    final response = await http
        .delete(
          Uri.parse("$_base/destinations/$destinationId/rating"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return RatingSummary.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not remove your rating");
  }
}
