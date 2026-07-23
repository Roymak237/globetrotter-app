import "package:flutter/material.dart";
import "../models/itinerary.dart";
import "../models/user.dart";
import "../services/auth_service.dart";

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();

  String? get token => _service.token;
  User? get currentUser => _service.currentUser;
  bool get isAuthenticated => _service.isAuthenticated;

  Future<void> loadToken() async {
    await _service.loadToken();
  }

  Future<bool> register({
    required String username,
    required String password,
    List<String>? preferences,
  }) async {
    return await _service.register(
      username: username,
      password: password,
      preferences: preferences,
    );
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    return await _service.login(username: username, password: password);
  }

  Future<void> logout() async {
    await _service.logout();
  }

  Future<List<Itinerary>> fetchItineraries() async {
    return await _service.fetchItineraries();
  }

  Future<void> createItinerary({
    required String title,
    required List<String> destinations,
    String? startDate,
    String? endDate,
    String? notes,
  }) async {
    return await _service.createItinerary(
      title: title,
      destinations: destinations,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
    );
  }

  Future<void> updateItinerary({
    required String itineraryId,
    String? title,
    List<String>? destinations,
    String? startDate,
    String? endDate,
    String? notes,
  }) async {
    return await _service.updateItinerary(
      itineraryId: itineraryId,
      title: title,
      destinations: destinations,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
    );
  }

  Future<void> deleteItinerary(String itineraryId) async {
    return await _service.deleteItinerary(itineraryId);
  }

  Future<void> shareItinerary({
    required String itineraryId,
    required String sharedWith,
  }) async {
    return await _service.shareItinerary(
      itineraryId: itineraryId,
      sharedWith: sharedWith,
    );
  }

  Future<void> revokeShare(String shareId) async {
    return await _service.revokeShare(shareId);
  }
}
