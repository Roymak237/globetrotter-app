class Share {
  final String id;
  final String itineraryId;
  final String owner;
  final String sharedWith;
  final String createdAt;

  Share({
    required this.id,
    required this.itineraryId,
    required this.owner,
    required this.sharedWith,
    required this.createdAt,
  });

  factory Share.fromJson(Map<String, dynamic> json) {
    return Share(
      id: json["id"] as String,
      itineraryId: json["itinerary_id"] as String,
      owner: json["owner"] as String,
      sharedWith: json["shared_with"] as String,
      createdAt: json["created_at"] as String? ?? "",
    );
  }
}
