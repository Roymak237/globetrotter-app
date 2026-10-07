class Destination {
  final String id;
  final String name;
  final String region;
  final String description;
  final List<String> tags;
  final double avgCostPerDay;
  final bool hasCostEstimate;

  /// What the figure buys: "per_day", "per_visit", "per_meal",
  /// "per_night", "per_trip", "free" or "none".
  ///
  /// Only four records are priced by the day. Labelling a museum's 2000 XAF
  /// admission as a daily cost overstates a day in Yaounde several times
  /// over, so the screens read this rather than assuming.
  final String costBasis;

  /// Where the daily cost came from. These are category estimates rather than
  /// surveyed prices, so the screen says so instead of implying precision.
  final String costNotes;
  final String address;
  final String locationNotes;

  /// "exact" when the pin is the place itself, "area" when it is the centre
  /// of the surrounding neighbourhood, empty when there is no pin. Many of
  /// these venues are known only by their quarter; a neighbourhood pin helps,
  /// but only if the map admits that is what it is.
  final String locationPrecision;
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
    this.costBasis = "",
    this.costNotes = "",
    this.address = "",
    this.locationNotes = "",
    this.locationPrecision = "",
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

  /// True when the pin locates the surrounding neighbourhood rather than the
  /// place itself, so the map can label it honestly.
  bool get isApproximateLocation =>
      hasCoordinates && locationPrecision == "area";

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json["id"] as String,
      name: json["name"] as String,
      region: json["region"] as String,
      description: json["description"] as String,
      tags: List<String>.from(json["tags"] ?? []),
      avgCostPerDay: (json["avg_cost_per_day"] as num?)?.toDouble() ?? 0,
      hasCostEstimate: json["avg_cost_per_day"] != null,
      costBasis: json["cost_basis"] ?? "",
      costNotes: json["cost_notes"] ?? "",
      address: json["address"] ?? "",
      locationNotes: json["location_notes"] ?? "",
      locationPrecision: json["location_precision"] ?? "",
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
        "cost_basis": costBasis,
        "cost_notes": costNotes,
        "address": address,
        "location_notes": locationNotes,
        "location_precision": locationPrecision,
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
