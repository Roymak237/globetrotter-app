class User {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String homeRegion;
  final String avatarUrl;
  final List<String> preferences;

  User({
    required this.id,
    required this.username,
    required this.preferences,
    this.displayName = "",
    this.email = "",
    this.homeRegion = "",
    this.avatarUrl = "",
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json["id"] as String? ?? "",
      username: json["username"] as String? ?? "",
      displayName: json["display_name"] as String? ?? "",
      email: json["email"] as String? ?? "",
      homeRegion: json["home_region"] as String? ?? "",
      avatarUrl: json["avatar_url"] as String? ?? "",
      preferences: List<String>.from(json["preferences"] ?? []),
    );
  }

  /// Keys match [User.fromJson] exactly so a cached profile round-trips.
  /// They are the server's field names, not Dart's, which keeps a stored
  /// profile and a freshly fetched one interchangeable.
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "username": username,
      "display_name": displayName,
      "email": email,
      "home_region": homeRegion,
      "avatar_url": avatarUrl,
      "preferences": preferences,
    };
  }
}
