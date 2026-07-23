import "dart:convert";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;

class ApiService {
  final String baseUrl = AppConstants.backendBaseUrl;

  Future<List<Destination>> searchDestinations({
    String? query,
    String? tag,
    String? region,
    int? maxCost,
  }) async {
    final params = <String, String>{};
    if (query != null && query.isNotEmpty) params["q"] = query;
    if (tag != null && tag.isNotEmpty) params["tag"] = tag;
    if (region != null && region.isNotEmpty) params["region"] = region;
    if (maxCost != null) params["max_cost"] = maxCost.toString();

    final uri = Uri.parse("$baseUrl${AppConstants.apiPrefix}/destinations")
        .replace(queryParameters: params);

    final response = await http.get(uri).timeout(AppConstants.apiTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => Destination.fromJson(e)).toList();
    }
    throw Exception("Failed to load destinations");
  }

  Future<Destination> getDestination(String id) async {
    final uri = Uri.parse("$baseUrl${AppConstants.apiPrefix}/destinations/$id");
    final response = await http.get(uri).timeout(AppConstants.apiTimeout);
    if (response.statusCode == 200) {
      return Destination.fromJson(json.decode(response.body));
    }
    throw Exception("Destination not found");
  }

  Future<List<Destination>> fetchRecommendations({
    required String token,
    int limit = 5,
  }) async {
    final uri = Uri.parse(
      "$baseUrl${AppConstants.apiPrefix}/recommendations",
    ).replace(queryParameters: {"limit": limit.toString()});

    final response = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token"},
    ).timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => Destination.fromJson(e)).toList();
    }
    throw Exception("Failed to load recommendations");
  }
}
