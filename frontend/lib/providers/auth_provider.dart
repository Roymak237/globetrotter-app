import "package:flutter/material.dart";

import "../models/itinerary.dart";
import "../models/user.dart";
import "../services/auth_service.dart";

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();

  AuthProvider() {
    _service.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _service.removeListener(notifyListeners);
    _service.dispose();
    super.dispose();
  }

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
    return _service.register(
      username: username,
      password: password,
      preferences: preferences,
    );
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    return _service.login(username: username, password: password);
  }

  Future<void> logout() async {
    await _service.logout();
  }

  Future<User> fetchProfile() async {
    return _service.fetchProfile();
  }

  Future<User> refreshToken() {
    return _service.refreshToken();
  }

  Future<User> updateProfile({
    String? displayName,
    String? email,
    String? homeRegion,
    String? avatarUrl,
    List<String>? preferences,
  }) {
    return _service.updateProfile(
      displayName: displayName,
      email: email,
      homeRegion: homeRegion,
      avatarUrl: avatarUrl,
      preferences: preferences,
    );
  }

  Future<User> updatePreferences({required List<String> preferences}) {
    return _service.updatePreferences(preferences: preferences);
  }

  Future<User> updateUsername({
    required String username,
    required String currentPassword,
  }) {
    return _service.updateUsername(
      username: username,
      currentPassword: currentPassword,
    );
  }

  Future<User> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _service.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<User> revokeOtherSessions() {
    return _service.revokeOtherSessions();
  }

  Future<void> deleteAccount({required String currentPassword}) {
    return _service.deleteAccount(currentPassword: currentPassword);
  }

  Future<List<Itinerary>> fetchItineraries() {
    return _service.fetchItineraries();
  }

  Future<void> createItinerary({
    required String title,
    required List<String> destinations,
    String? startDate,
    String? endDate,
    String? notes,
  }) {
    return _service.createItinerary(
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
  }) {
    return _service.updateItinerary(
      itineraryId: itineraryId,
      title: title,
      destinations: destinations,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
    );
  }

  Future<void> deleteItinerary(String itineraryId) {
    return _service.deleteItinerary(itineraryId);
  }

  Future<void> shareItinerary({
    required String itineraryId,
    required String sharedWith,
  }) {
    return _service.shareItinerary(
      itineraryId: itineraryId,
      sharedWith: sharedWith,
    );
  }

  Future<void> revokeShare(String shareId) {
    return _service.revokeShare(shareId);
  }
}
