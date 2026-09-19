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

  Widget get _placeholder => Semantics(
        label: "Destination image unavailable for ${destination.name}",
        child: Container(
          color: AppTheme.primarySoft,
          alignment: Alignment.center,
          child: const Icon(
            Icons.landscape_outlined,
            size: 44,
            color: AppTheme.primary,
          ),
        ),
      );
}
