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

  Future<void> _persistToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("auth_token", token);
  }

  Future<void> _replaceSession({
    required String token,
    required User user,
  }) async {
    await _persistToken(token);
    _currentUser = user;
    notifyListeners();
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    final decoded = json.decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<User> _applyRotatedSession(
    http.Response response, {
    required String fallback,
  }) async {
    if (response.statusCode != 200) {
      final body = _decodeBody(response);
      throw Exception(body["error"] ?? fallback);
    }
    final body = _decodeBody(response);
    final token = body["token"] as String?;
    final userJson = body["user"];
    if (token == null || userJson is! Map<String, dynamic>) {
      throw Exception(fallback);
    }
    final user = User.fromJson(userJson);
    await _replaceSession(token: token, user: user);
    return user;
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("auth_token");
    if (_token != null) {
      _currentUser = User(
        id: "",
        username: "",
        preferences: const [],
      );
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

    if (response.statusCode == 201) return true;
    final body = _decodeBody(response);
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
      final data = _decodeBody(response);
      final token = data["token"] as String?;
      if (token == null) throw Exception("Login failed");
      await _persistToken(token);
      _currentUser = User(
        id: "",
        username: username,
        preferences: const [],
      );
      notifyListeners();
      return true;
    }
    final body = _decodeBody(response);
    throw Exception(body["error"] ?? "Login failed");
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("auth_token");
    notifyListeners();
  }

  Future<User> fetchProfile() async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/me",
    );
    final response = await http.get(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
    if (response.statusCode == 200) {
      _currentUser = User.fromJson(_decodeBody(response));
      notifyListeners();
      return _currentUser!;
    }
    final body = _decodeBody(response);
    throw Exception(body["error"] ?? "Failed to fetch profile");
  }

  Future<User> refreshToken() async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/refresh",
    );
    final response = await http.post(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
    return _applyRotatedSession(
      response,
      fallback: "Failed to refresh session",
    );
  }

  Future<User> updateProfile({
    String? displayName,
    String? email,
    String? homeRegion,
    String? avatarUrl,
    List<String>? preferences,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final body = <String, dynamic>{};
    if (displayName != null) body["display_name"] = displayName;
    if (email != null) body["email"] = email;
    if (homeRegion != null) body["home_region"] = homeRegion;
    if (avatarUrl != null) body["avatar_url"] = avatarUrl;
    if (preferences != null) body["preferences"] = preferences;
    if (body.isEmpty) throw Exception("No profile changes supplied");

    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/profile",
    );
    final response = await http
        .patch(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode(body),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      _currentUser = User.fromJson(_decodeBody(response));
      notifyListeners();
      return _currentUser!;
    }
    final data = _decodeBody(response);
    throw Exception(data["error"] ?? "Failed to update profile");
  }

  Future<User> updatePreferences({required List<String> preferences}) {
    return updateProfile(preferences: preferences);
  }

  Future<User> updateUsername({
    required String username,
    required String currentPassword,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/username",
    );
    final response = await http
        .patch(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode({
            "username": username,
            "current_password": currentPassword,
          }),
        )
        .timeout(AppConstants.apiTimeout);
    return _applyRotatedSession(
      response,
      fallback: "Failed to change username",
    );
  }

  Future<User> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/password",
    );
    final response = await http
        .patch(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode({
            "current_password": currentPassword,
            "new_password": newPassword,
          }),
        )
        .timeout(AppConstants.apiTimeout);
    return _applyRotatedSession(
      response,
      fallback: "Failed to change password",
    );
  }

  Future<User> revokeOtherSessions() async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/sessions/revoke",
    );
    final response = await http.post(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
    return _applyRotatedSession(
      response,
      fallback: "Failed to sign out other sessions",
    );
  }

  Future<void> deleteAccount({required String currentPassword}) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/auth/account",
    );
    final response = await http
        .delete(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $_token",
          },
          body: json.encode({"current_password": currentPassword}),
        )
        .timeout(AppConstants.apiTimeout);
    if (response.statusCode != 204) {
      final body = _decodeBody(response);
      throw Exception(body["error"] ?? "Failed to delete account");
    }
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
    final response = await http.get(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
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
      final body = _decodeBody(response);
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
      final data = _decodeBody(response);
      throw Exception(data["error"] ?? "Failed to update itinerary");
    }
  }

  Future<void> deleteItinerary(String itineraryId) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/itineraries/$itineraryId",
    );
    final response = await http.delete(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
    if (response.statusCode != 200) {
      final data = _decodeBody(response);
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
      final data = _decodeBody(response);
      throw Exception(data["error"] ?? "Failed to share itinerary");
    }
  }

  Future<void> revokeShare(String shareId) async {
    if (_token == null) throw Exception("Not authenticated");
    final uri = Uri.parse(
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/shares/$shareId",
    );
    final response = await http.delete(
      uri,
      headers: {"Authorization": "Bearer $_token"},
    ).timeout(AppConstants.apiTimeout);
    if (response.statusCode != 200) {
      final data = _decodeBody(response);
      throw Exception(data["error"] ?? "Failed to revoke share");
    }
  }
}
