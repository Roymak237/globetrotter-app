class User {
  final String id;
  final String username;
  final List<String> preferences;

  User({
    required this.id,
    required this.username,
    required this.preferences,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json["id"] as String,
      username: json["username"] as String,
      preferences: List<String>.from(json["preferences"] ?? []),
    );
  }
}
