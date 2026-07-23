import "dart:convert";
import "package:flutter/material.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";

import "../models/itinerary.dart";

class AuthService extends ChangeNotifier {
  String? _token;
  User? _currentUser;

  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("auth_token");
    if (_token != null) {
      _currentUser = User(id: "", username: "", preferences: []);
    }
    notifyListeners();
  }

  Future<bool> register({
    required String username,
    required String password,
    List<String>? preferences,
  }) async {
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/register",
    );
    final response = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "username": username,
            "password": password,
            "preferences": preferences ?? [],
          }),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 201) {
      return true;
    }
    final body = json.decode(response.body);
    throw Exception(body["error"] ?? "Registration failed");
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/login",
    );
    final response = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "username": username,
            "password": password,
          }),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _token = data["token"] as String;
      _currentUser = User(id: "", username: username, preferences: []);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("auth_token", _token!);
      notifyListeners();
      return true;
    }
    final body = json.decode(response.body);
    throw Exception(body["error"] ?? "Login failed");
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("auth_token");
    notifyListeners();
  }

  Future<List<Itinerary>> fetchItineraries() async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries",
    );
    final response = await http
        .get(
          uri,
          headers: {"Authorization": "Bearer $_token"},
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => Itinerary.fromJson(e)).toList();
    }
    throw Exception("Failed to load itineraries");
  }

  Future<void> createItinerary({
    required String title,
    required List<String> destinations,
    String? startDate,
    String? endDate,
    String? notes,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries",
    );
    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode({
            "title": title,
            "destinations": destinations,
            "start_date": startDate ?? "",
            "end_date": endDate ?? "",
            "notes": notes ?? "",
          }),
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 201) {
      final body = json.decode(response.body);
      throw Exception(body["error"] ?? "Failed to create itinerary");
    }
  }

  Future<void> updateItinerary({
    required String itineraryId,
    String? title,
    List<String>? destinations,
    String? startDate,
    String? endDate,
    String? notes,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries/$itineraryId",
    );
    final body = <String, dynamic>{};
    if (title != null) body["title"] = title;
    if (destinations != null) body["destinations"] = destinations;
    if (startDate != null) body["start_date"] = startDate;
    if (endDate != null) body["end_date"] = endDate;
    if (notes != null) body["notes"] = notes;

    final response = await http
        .put(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode(body),
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data["error"] ?? "Failed to update itinerary");
    }
  }

  Future<void> deleteItinerary(String itineraryId) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries/$itineraryId",
    );
    final response = await http
        .delete(
          uri,
          headers: {"Authorization": "Bearer $_token"},
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data["error"] ?? "Failed to delete itinerary");
    }
  }

  Future<void> shareItinerary({
    required String itineraryId,
    required String sharedWith,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries/$itineraryId/share",
    );
    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode({"shared_with": sharedWith}),
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 201) {
      final data = json.decode(response.body);
      throw Exception(data["error"] ?? "Failed to share itinerary");
    }
  }

  Future<void> revokeShare(String shareId) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/shares/$shareId",
    );
    final response = await http
        .delete(
          uri,
          headers: {"Authorization": "Bearer $_token"},
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data["error"] ?? "Failed to revoke share");
    }
  }
}
