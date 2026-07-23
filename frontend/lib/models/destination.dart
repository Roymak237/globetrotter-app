class Destination {
  final String id;
  final String name;
  final String region;
  final String description;
  final List<String> tags;
  final double avgCostPerDay;
  final List<String> highlights;

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.tags,
    required this.avgCostPerDay,
    required this.highlights,
  });

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json["id"] as String,
      name: json["name"] as String,
      region: json["region"] as String,
      description: json["description"] as String,
      tags: List<String>.from(json["tags"] ?? []),
      avgCostPerDay: (json["avg_cost_per_day"] is int)
          ? (json["avg_cost_per_day"] as int).toDouble()
          : (json["avg_cost_per_day"] ?? 0.0).toDouble(),
      highlights: List<String>.from(json["highlights"] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "region": region,
        "description": description,
        "tags": tags,
        "avg_cost_per_day": avgCostPerDay.toInt(),
        "highlights": highlights,
      };
}
