import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../utils/destination_cost.dart";
import "../utils/theme.dart";
import "../widgets/comments_section.dart";
import "../widgets/destination_image.dart";
import "../widgets/destination_map.dart";
import "../widgets/favorite_button.dart";

class DestinationDetailScreen extends StatelessWidget {
  const DestinationDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isFrench = localizations.locale.languageCode == "fr";
    final destination =
        ModalRoute.of(context)!.settings.arguments as Destination;
    final cost = destinationCostLabel(context, destination, perDay: true);
    final galleryAssets = destination.additionalImageAssets
        .map((asset) => asset.trim())
        .where((asset) =>
            asset.isNotEmpty && asset != destination.imageAsset.trim())
        .toSet()
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 290,
            pinned: true,
            backgroundColor: AppTheme.primaryDark,
            foregroundColor: Colors.white,
            title: Text(destination.name),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FavoriteButton(destination: destination),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _DestinationHeroImage(destination: destination),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xC22A1055)],
                        stops: [0.35, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "FIELD GUIDE / ${destination.region.toUpperCase()}",
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          destination.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: AppTheme.displayFontFamily,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetaTile(
                          icon: Icons.location_on_outlined,
                          label: isFrench ? "RÉGION" : "REGION",
                          value: destination.region,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetaTile(
                          icon: Icons.payments_outlined,
                          label: isFrench
                              ? "COÛT JOURNALIER ESTIMÉ"
                              : "EST. DAILY COST",
                          value: cost,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  if (destination.address.isNotEmpty) ...[
                    Text(isFrench ? "Adresse" : "Address",
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    SelectableText(destination.address),
                    const SizedBox(height: 18),
                  ],
                  if (destination.locationNotes.isNotEmpty) ...[
                    Text(isFrench ? "Notes de localisation" : "Location notes",
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(destination.locationNotes),
                    const SizedBox(height: 18),
                  ],
                  if (destination.locationSources.isNotEmpty) ...[
                    Text(
                        isFrench
                            ? "Sources de localisation"
                            : "Location sources",
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ...destination.locationSources.map((source) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SelectableText(source),
                        )),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.onTheMap,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontFamily: AppTheme.displayFontFamily,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            if (destination.hasCoordinates)
                              Text(
                                localizations.mapStartingPoint,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      if (destination.hasCoordinates)
                        Text(
                          "${destination.latitude!.toStringAsFixed(3)}, ${destination.longitude!.toStringAsFixed(3)}",
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (destination.hasCoordinates)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: DestinationMap(
                        destinations: [destination],
                        selectedDestination: destination,
                        height: 230,
                        zoom: 14.5,
                        compact: true,
                      ),
                    )
                  else
                    Text(
                      isFrench
                          ? "Localisation en attente de vérification. Aucune position affichée sur la carte."
                          : "Location pending verification. No map pin is shown.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 26),
                  Text(
                    localizations.whyGo,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontFamily: AppTheme.displayFontFamily,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    destination.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.55,
                        ),
                  ),
                  if (galleryAssets.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(isFrench ? "Autres photos" : "More photos",
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: galleryAssets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) => ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
                          child: Image.asset(
                            "assets/images/${galleryAssets[index]}",
                            width: 220,
                            height: 150,
                            fit: BoxFit.cover,
                            semanticLabel: "${destination.name} — ${index + 1}",
                            errorBuilder: (_, __, ___) => SizedBox(
                              width: 220,
                              child: Center(
                                child: Text(isFrench
                                    ? "Photo non disponible"
                                    : "Photo not available"),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (destination.highlights.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(
                      localizations.fieldNotes,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                    ),
                    const SizedBox(height: 10),
                    ...destination.highlights.map(
                      (highlight) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                highlight,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (destination.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: destination.tags
                          .map(
                            (tag) => Chip(
                              label: Text(tag),
                              backgroundColor: AppTheme.primarySoft,
                              side: BorderSide.none,
                              labelStyle: const TextStyle(
                                color: AppTheme.primaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    localizations.savePlaceMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(color: AppTheme.border),
                  const SizedBox(height: 20),
                  CommentsSection(destinationId: destination.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 19),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.secondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _DestinationHeroImage extends StatelessWidget {
  final Destination destination;

  const _DestinationHeroImage({required this.destination});

  @override
  Widget build(BuildContext context) {
    return DestinationImage(
      destination: destination,
      fit: BoxFit.cover,
    );
  }
}
