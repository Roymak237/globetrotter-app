import "package:flutter/material.dart";

/// Another catalogue destination close to the one being viewed.
class NearbyPlace {
  final String id;
  final String name;
  final String region;
  final List<String> tags;
  final String imageUrl;
  final String imageAsset;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final double ratingAverage;
  final int ratingCount;

  const NearbyPlace({
    required this.id,
    required this.name,
    required this.region,
    required this.tags,
    required this.imageUrl,
    required this.imageAsset,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.ratingAverage,
    required this.ratingCount,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> json) {
    final rating = json["rating"] as Map<String, dynamic>? ?? const {};
    return NearbyPlace(
      id: json["id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      region: json["region"]?.toString() ?? "",
      tags: (json["tags"] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .toList(),
      imageUrl: json["image_url"]?.toString() ?? "",
      imageAsset: json["image_asset"]?.toString() ?? "",
      latitude: (json["latitude"] as num?)?.toDouble() ?? 0,
      longitude: (json["longitude"] as num?)?.toDouble() ?? 0,
      distanceKm: (json["distance_km"] as num?)?.toDouble() ?? 0,
      ratingAverage: (rating["average"] as num?)?.toDouble() ?? 0,
      ratingCount: (rating["count"] as num?)?.toInt() ?? 0,
    );
  }

  /// Distance phrased the way a traveller would say it.
  String get distanceLabel => distanceKm < 1
      ? "${(distanceKm * 1000).round()} m away"
      : "${distanceKm.toStringAsFixed(1)} km away";
}

/// A single real-world service near a destination, sourced from OpenStreetMap.
class Amenity {
  final String name;
  final String kind;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String openingHours;
  final String phone;
  final String website;

  const Amenity({
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.openingHours,
    required this.phone,
    required this.website,
  });

  factory Amenity.fromJson(Map<String, dynamic> json) => Amenity(
        name: json["name"]?.toString() ?? "",
        kind: json["kind"]?.toString() ?? "place",
        latitude: (json["latitude"] as num?)?.toDouble() ?? 0,
        longitude: (json["longitude"] as num?)?.toDouble() ?? 0,
        distanceKm: (json["distance_km"] as num?)?.toDouble() ?? 0,
        openingHours: json["opening_hours"]?.toString() ?? "",
        phone: json["phone"]?.toString() ?? "",
        website: json["website"]?.toString() ?? "",
      );

  String get distanceLabel => distanceKm < 1
      ? "${(distanceKm * 1000).round()} m"
      : "${distanceKm.toStringAsFixed(1)} km";

  /// "fast_food" reads badly in a list; show "Fast food".
  String get kindLabel {
    final words = kind.replaceAll("_", " ").trim();
    if (words.isEmpty) return "Place";
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// Amenities of one category, with the label the backend chose for it.
class AmenityGroup {
  final String category;
  final String label;
  final List<Amenity> items;

  const AmenityGroup({
    required this.category,
    required this.label,
    required this.items,
  });

  factory AmenityGroup.fromJson(Map<String, dynamic> json) => AmenityGroup(
        category: json["category"]?.toString() ?? "",
        label: json["label"]?.toString() ?? "Nearby",
        items: (json["items"] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Amenity.fromJson)
            .toList(),
      );

  IconData get icon {
    switch (category) {
      case "food":
        return Icons.restaurant_rounded;
      case "money":
        return Icons.account_balance_rounded;
      case "fuel":
        return Icons.local_gas_station_rounded;
      case "health":
        return Icons.local_pharmacy_rounded;
      case "safety":
        return Icons.local_police_rounded;
      default:
        return Icons.place_rounded;
    }
  }
}

/// How a destination is rated overall, and how the viewer rated it.
class RatingSummary {
  final double average;
  final int count;

  /// The signed-in traveller's own rating, or null if they have not rated it.
  final int? mine;

  const RatingSummary({
    required this.average,
    required this.count,
    required this.mine,
  });

  static const RatingSummary empty =
      RatingSummary(average: 0, count: 0, mine: null);

  factory RatingSummary.fromJson(Map<String, dynamic> json) => RatingSummary(
        average: (json["average"] as num?)?.toDouble() ?? 0,
        count: (json["count"] as num?)?.toInt() ?? 0,
        mine: (json["mine"] as num?)?.toInt(),
      );

  bool get hasRatings => count > 0;

  String get averageLabel => average.toStringAsFixed(1);

  String get countLabel => count == 1 ? "1 rating" : "$count ratings";
}
