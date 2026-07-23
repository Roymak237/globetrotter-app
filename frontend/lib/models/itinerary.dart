class Itinerary {
  final String id;
  final String username;
  final String title;
  final List<String> destinations;
  final String startDate;
  final String endDate;
  final String notes;
  final String createdAt;

  Itinerary({
    required this.id,
    required this.username,
    required this.title,
    required this.destinations,
    required this.startDate,
    required this.endDate,
    required this.notes,
    required this.createdAt,
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    return Itinerary(
      id: json["id"] as String,
      username: json["username"] as String,
      title: json["title"] as String,
      destinations: List<String>.from(json["destinations"] ?? []),
      startDate: json["start_date"] as String? ?? "",
      endDate: json["end_date"] as String? ?? "",
      notes: json["notes"] as String? ?? "",
      createdAt: json["created_at"] as String? ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "username": username,
        "title": title,
        "destinations": destinations,
        "start_date": startDate,
        "end_date": endDate,
        "notes": notes,
      };
}
