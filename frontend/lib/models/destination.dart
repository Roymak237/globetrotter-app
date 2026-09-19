class Destination {
  final String id;
  final String name;
  final String region;
  final String description;
  final List<String> tags;
  final double avgCostPerDay;
  final bool hasCostEstimate;
  final String address;
  final String locationNotes;
  final List<String> locationSources;
  final List<String> additionalImageAssets;
  final List<String> highlights;
  final String imageUrl;
  final String imageAsset;
  final String imageAttribution;
  final double? latitude;
  final double? longitude;
  final int matchScore;

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.tags,
    required this.avgCostPerDay,
    required this.highlights,
    this.hasCostEstimate = true,
    this.address = "",
    this.locationNotes = "",
    this.locationSources = const [],
    this.additionalImageAssets = const [],
    this.imageUrl = "",
    this.imageAsset = "",
    this.imageAttribution = "",
    this.latitude,
    this.longitude,
    this.matchScore = 0,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json["id"] as String,
      name: json["name"] as String,
      region: json["region"] as String,
      description: json["description"] as String,
      tags: List<String>.from(json["tags"] ?? []),
      avgCostPerDay: (json["avg_cost_per_day"] as num?)?.toDouble() ?? 0,
      hasCostEstimate: json["avg_cost_per_day"] != null,
      address: json["address"] ?? "",
      locationNotes: json["location_notes"] ?? "",
      locationSources: List<String>.from(json["location_sources"] ?? []),
      additionalImageAssets:
          List<String>.from(json["additional_image_assets"] ?? []),
      highlights: List<String>.from(json["highlights"] ?? []),
      imageUrl: json["image_url"] ?? "",
      imageAsset: json["image_asset"] ?? "",
      imageAttribution: json["image_attribution"] ?? "",
      latitude: (json["latitude"] as num?)?.toDouble(),
      longitude: (json["longitude"] as num?)?.toDouble(),
      matchScore: (json["match_score"] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "region": region,
        "description": description,
        "tags": tags,
        "avg_cost_per_day": hasCostEstimate ? avgCostPerDay.toInt() : null,
        "address": address,
        "location_notes": locationNotes,
        "location_sources": locationSources,
        "additional_image_assets": additionalImageAssets,
        "highlights": highlights,
        "image_url": imageUrl,
        "image_asset": imageAsset,
        "image_attribution": imageAttribution,
        if (latitude != null) "latitude": latitude,
        if (longitude != null) "longitude": longitude,
        "match_score": matchScore,
      };
}
