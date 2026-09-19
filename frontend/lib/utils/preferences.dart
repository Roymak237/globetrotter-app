import "package:flutter/material.dart";

class TravelPreferenceOption {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  const TravelPreferenceOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}

const travelPreferenceOptions = [
  TravelPreferenceOption(
    id: "relaxation",
    label: "Slow days",
    description: "Coastlines and easy escapes",
    icon: Icons.beach_access_outlined,
  ),
  TravelPreferenceOption(
    id: "culture",
    label: "Culture",
    description: "Stories, people, and places",
    icon: Icons.diversity_3_outlined,
  ),
  TravelPreferenceOption(
    id: "nature",
    label: "Nature",
    description: "Green spaces and fresh air",
    icon: Icons.forest_outlined,
  ),
  TravelPreferenceOption(
    id: "hiking",
    label: "Hiking",
    description: "Trails with a view",
    icon: Icons.directions_walk_outlined,
  ),
  TravelPreferenceOption(
    id: "food",
    label: "Food",
    description: "Markets and local flavors",
    icon: Icons.restaurant_outlined,
  ),
  TravelPreferenceOption(
    id: "wildlife",
    label: "Wildlife",
    description: "A closer look at nature",
    icon: Icons.pets_outlined,
  ),
  TravelPreferenceOption(
    id: "family",
    label: "Family",
    description: "Easy days for everyone",
    icon: Icons.family_restroom_outlined,
  ),
  TravelPreferenceOption(
    id: "history",
    label: "History",
    description: "Memory written into place",
    icon: Icons.account_balance_outlined,
  ),
  TravelPreferenceOption(
    id: "shopping",
    label: "Markets",
    description: "Crafts, finds, and color",
    icon: Icons.storefront_outlined,
  ),
  TravelPreferenceOption(
    id: "nightlife",
    label: "After dark",
    description: "City lights and late tables",
    icon: Icons.nightlife_outlined,
  ),
];

String preferenceCountLabel(int count) =>
    "$count interest${count == 1 ? "" : "s"} selected";

String preferenceLabel(String id) {
  for (final option in travelPreferenceOptions) {
    if (option.id == id) return option.label;
  }
  return id;
}
