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
      "groceries": Icons.local_grocery_store_outlined,
      "retail": Icons.storefront_outlined,
      "gaming": Icons.sports_esports_outlined,
      "entertainment": Icons.sports_esports_outlined,
      "nightlife": Icons.nightlife_outlined,
      "school": Icons.school_outlined,
      "education": Icons.school_outlined,
      "university": Icons.school_outlined,
      "institute": Icons.school_outlined,
      "library": Icons.local_library_outlined,
      "health": Icons.local_hospital_outlined,
      "medicine": Icons.local_hospital_outlined,
      "park": Icons.park_outlined,
      "garden": Icons.local_florist_outlined,
      "zoo": Icons.pets_outlined,
      "wildlife": Icons.pets_outlined,
      "waterfall": Icons.water_outlined,
      "lake": Icons.water_outlined,
      "beach": Icons.beach_access_outlined,
      "mountain": Icons.terrain_outlined,
      "hiking": Icons.hiking_outlined,
      "city": Icons.location_city_outlined,
      "landmark": Icons.location_city_outlined,
      "architecture": Icons.apartment_outlined,
      "tourist": Icons.photo_camera_outlined,
      "art": Icons.palette_outlined,
      "culture": Icons.theater_comedy_outlined,
      "sport": Icons.sports_soccer_outlined,
      "recreation": Icons.sports_soccer_outlined,
      "pool": Icons.pool_outlined,
      "leisure": Icons.weekend_outlined,
      "relaxation": Icons.spa_outlined,
      "family": Icons.family_restroom_outlined,
      "adventure": Icons.explore_outlined,
      "community": Icons.groups_outlined,
    };
    for (final tag in destination.tags) {
      final icon = byTag[tag.toLowerCase()];
      if (icon != null) return icon;
    }
    return Icons.landscape_outlined;
  }

  /// The two tones a photo-less card is painted in.
  ///
  /// Fifty identical beige tiles read as a loading failure even when each
  /// one is deliberate, so the colour follows the category. A row of
  /// restaurants and a row of churches no longer look like the same
  /// missing asset repeated.
  ///
  /// These are not photographs and are not pretending to be. Commons holds
  /// no freely licensed picture of a cyber cafe in Biyem-Assi, and putting
  /// a stock interior there would be a claim about a place we have never
  /// seen.
  List<Color> get _placeholderTones {
    const byTag = <String, List<Color>>{
      "dining": [Color(0xFFE8B4A0), Color(0xFFC9703A)],
      "food": [Color(0xFFE8B4A0), Color(0xFFC9703A)],
      "restaurant": [Color(0xFFE8B4A0), Color(0xFFC9703A)],
      "market": [Color(0xFFF0C98A), Color(0xFFD98E2B)],
      "shopping": [Color(0xFFF0C98A), Color(0xFFD98E2B)],
      "supermarket": [Color(0xFFF0C98A), Color(0xFFD98E2B)],
      "retail": [Color(0xFFF0C98A), Color(0xFFD98E2B)],
      "gaming": [Color(0xFFB8C6DE), Color(0xFF1F3A63)],
      "entertainment": [Color(0xFFB8C6DE), Color(0xFF1F3A63)],
      "education": [Color(0xFFA9C4D9), Color(0xFF2F5A7A)],
      "school": [Color(0xFFA9C4D9), Color(0xFF2F5A7A)],
      "university": [Color(0xFFA9C4D9), Color(0xFF2F5A7A)],
      "religion": [Color(0xFFD9C9E2), Color(0xFF6B4A7A)],
      "landmark": [Color(0xFFD9C9E2), Color(0xFF6B4A7A)],
      "monument": [Color(0xFFD9C9E2), Color(0xFF6B4A7A)],
      "history": [Color(0xFFD9C9E2), Color(0xFF6B4A7A)],
      "museum": [Color(0xFFD9C9E2), Color(0xFF6B4A7A)],
      "recreation": [Color(0xFFAFCFA8), Color(0xFF4F7A3F)],
      "sport": [Color(0xFFAFCFA8), Color(0xFF4F7A3F)],
      "leisure": [Color(0xFFAFCFA8), Color(0xFF4F7A3F)],
      "park": [Color(0xFFAFCFA8), Color(0xFF4F7A3F)],
      "nature": [Color(0xFFAFCFA8), Color(0xFF4F7A3F)],
      "tourist": [Color(0xFFF2D9A8), Color(0xFFB4462A)],
      "culture": [Color(0xFFF2D9A8), Color(0xFFB4462A)],
    };
    for (final tag in destination.tags) {
      final tones = byTag[tag.toLowerCase()];
      if (tones != null) return tones;
    }
    return const [AppTheme.primarySoft, AppTheme.clay];
  }

  Widget get _placeholder {
    final tones = _placeholderTones;
    return Semantics(
      label: "No photograph available for ${destination.name}",
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tones.first, tones.last],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A watermark sized to the card, so the same widget works for a
            // 72 px list thumbnail and a full-bleed detail header.
            final short = constraints.biggest.shortestSide;
            final glyph = short.isFinite ? short : 160.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -glyph * 0.22,
                  bottom: -glyph * 0.26,
                  child: Icon(
                    _placeholderIcon,
                    size: glyph * 0.92,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                Center(
                  child: Icon(
                    _placeholderIcon,
                    size: (glyph * 0.26).clamp(20.0, 52.0),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
