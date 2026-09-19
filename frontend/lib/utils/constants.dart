class AppConstants {
  /// Base URL of the backend API.
  ///
  /// Defaults to localhost for development. Production builds override it:
  ///   flutter build web --dart-define=BACKEND_BASE_URL=https://your-domain
  static const String backendBaseUrl = String.fromEnvironment(
    "BACKEND_BASE_URL",
    defaultValue: "http://127.0.0.1:5000",
  );
  static const String apiPrefix = "/api";
  static const Duration apiTimeout = Duration(seconds: 30);
}
