import "package:flutter/material.dart";

import "../models/destination.dart";
import "../utils/destination_media.dart";
import "../utils/theme.dart";

class DestinationImage extends StatelessWidget {
  final Destination destination;
  final BoxFit fit;

  const DestinationImage({
    super.key,
    required this.destination,
    this.fit = BoxFit.cover,
  });

  DestinationMedia? get _verifiedFallback => mediaFallbackFor(destination);

  String _semanticLabel(String? attribution) {
    final source = attribution?.trim() ?? "";
    if (source.isEmpty) return "Image of ${destination.name}";
    return "Image of ${destination.name}. $source";
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _placeholder;
    final url = destination.imageUrl.trim();
    final verified = _verifiedFallback;

    if (destination.imageAsset.trim().isNotEmpty) {
      return Image.asset(
        "assets/images/${destination.imageAsset}",
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        semanticLabel: _semanticLabel(destination.imageAttribution),
        errorBuilder: (_, __, ___) => url.isNotEmpty
            ? _networkImage(
                url,
                attribution: destination.imageAttribution,
                fallback:
                    verified == null ? fallback : _verifiedImage(verified),
              )
            : verified == null
                ? fallback
                : _verifiedImage(verified),
      );
    }

    if (url.isNotEmpty) {
      return _networkImage(
        url,
        attribution: destination.imageAttribution,
        fallback: verified == null ? fallback : _verifiedImage(verified),
      );
    }

    if (verified != null) return _verifiedImage(verified);
    return fallback;
  }

  Widget _verifiedImage(DestinationMedia media) => _networkImage(
        media.url,
        attribution: media.attribution,
        fallback: _placeholder,
      );

  Widget _networkImage(
    String url, {
    required String attribution,
    required Widget fallback,
  }) {
    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: _semanticLabel(attribution),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// An icon that matches what the place is, rather than a generic hillside.
  ///
  /// Some destinations genuinely have no photograph, and inventing one would
  /// be worse than showing none. A card for a mosque marked with a landscape
  /// icon just looks broken; one marked with a mosque icon reads as a place
  /// we simply have no picture of yet.
  IconData get _placeholderIcon {
    const byTag = <String, IconData>{
      "mosque": Icons.mosque_outlined,
      "religion": Icons.place_outlined,
      "museum": Icons.museum_outlined,
      "monument": Icons.account_balance_outlined,
      "history": Icons.account_balance_outlined,
      "hotel": Icons.hotel_outlined,
      "lodging": Icons.hotel_outlined,
      "restaurant": Icons.restaurant_outlined,
      "dining": Icons.restaurant_outlined,
      "food": Icons.restaurant_outlined,
      "market": Icons.storefront_outlined,
      "shopping": Icons.storefront_outlined,
      "supermarket": Icons.local_grocery_store_outlined,
      "gaming": Icons.sports_esports_outlined,
      "school": Icons.school_outlined,
      "education": Icons.school_outlined,
      "health": Icons.local_hospital_outlined,
      "park": Icons.park_outlined,
      "zoo": Icons.pets_outlined,
      "wildlife": Icons.pets_outlined,
      "waterfall": Icons.water_outlined,
      "lake": Icons.water_outlined,
      "beach": Icons.beach_access_outlined,
      "mountain": Icons.terrain_outlined,
      "hiking": Icons.hiking_outlined,
      "city": Icons.location_city_outlined,
    };
    for (final tag in destination.tags) {
      final icon = byTag[tag.toLowerCase()];
      if (icon != null) return icon;
    }
    return Icons.landscape_outlined;
  }

  Widget get _placeholder => Semantics(
        label: "Destination image unavailable for ${destination.name}",
        child: Container(
          color: AppTheme.primarySoft,
          alignment: Alignment.center,
          child: Icon(
            _placeholderIcon,
            size: 44,
            color: AppTheme.primary,
          ),
        ),
      );
}
