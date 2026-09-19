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
}
