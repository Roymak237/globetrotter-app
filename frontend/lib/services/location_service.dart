import "dart:convert";

import "package:globetrotter/models/shared_location.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;

/// Publishes the traveller's own position and reads back their group's.
///
/// Like the other services here it is stateless and takes the token per call.
/// It deliberately offers no way to fetch "everyone" — the server scopes every
/// read to the caller's groups, and there is no endpoint that would do
/// otherwise.
class LocationService {
  final String _base =
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}";

  Map<String, String> _headers(String token, {bool json = false}) => {
        "Authorization": "Bearer $token",
        if (json) "Content-Type": "application/json",
      };

  Never _fail(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body["error"] != null) {
        throw Exception(body["error"].toString());
      }
    } on FormatException {
      // Body was not JSON; fall through to the generic message below.
    }
    throw Exception(fallback);
  }

  /// Replaces the traveller's shared position with where they are now.
  Future<void> publish({
    required String token,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final response = await http
        .put(
          Uri.parse("$_base/me/location"),
          headers: _headers(token, json: true),
          body: jsonEncode({
            "latitude": latitude,
            "longitude": longitude,
            if (accuracy != null) "accuracy": accuracy,
          }),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) return;
    _fail(response, "Could not share your location");
  }

  /// Erases the stored position, so nobody can see it any more.
  Future<void> stopSharing(String token) async {
    final response = await http
        .delete(
          Uri.parse("$_base/me/location"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) return;
    _fail(response, "Could not stop sharing your location");
  }

  /// Live positions of people the traveller shares a group with.
  Future<List<SharedLocation>> fetchCompanions(String token) async {
    final response = await http
        .get(
          Uri.parse("$_base/location/companions"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final entries = body is Map ? body["companions"] : null;
      if (entries is! List) return const [];
      return entries
          .whereType<Map<String, dynamic>>()
          .map(SharedLocation.tryFromJson)
          .whereType<SharedLocation>()
          .toList();
    }
    _fail(response, "Could not load your group's locations");
  }
}
