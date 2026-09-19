import "package:flutter/material.dart";

import "../models/destination.dart";
import "../utils/destination_cost.dart";
import "../utils/theme.dart";
import "destination_image.dart";
import "favorite_button.dart";

class DestinationCard extends StatelessWidget {
  final Destination destination;
  final VoidCallback? onTap;

  const DestinationCard({
    super.key,
    required this.destination,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tags = destination.tags.take(3).join("  •  ");
    final cost = destinationCostLabel(context, destination);

    return Semantics(
      button: onTap != null,
      label:
          "${destination.name}, ${destination.region}, ${destinationCostLabel(context, destination, perDay: true)}${destination.matchScore > 0 ? ", matches ${destination.matchScore} interests" : ""}",
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.65,
                child: _DestinationImage(destination: destination),
              ),
              ClipPath(
                clipper: _TicketBodyClipper(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                  color: AppTheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              destination.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontFamily: AppTheme.displayFontFamily,
                                    height: 1.05,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            cost,
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppTheme.secondary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 17,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              destination.region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          if (onTap != null)
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppTheme.primary,
                              size: 19,
                            ),
                        ],
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          tags.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                    letterSpacing: 0.7,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketBodyClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const notchRadius = 11.0;
    final middle = size.height * 0.46;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, middle - notchRadius)
      ..arcToPoint(
        Offset(size.width, middle + notchRadius),
        radius: const Radius.circular(notchRadius),
        clockwise: false,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, middle + notchRadius)
      ..arcToPoint(
        Offset(0, middle - notchRadius),
        radius: const Radius.circular(notchRadius),
        clockwise: false,
      )
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DestinationImage extends StatelessWidget {
  final Destination destination;

  const _DestinationImage({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DestinationImage(destination: destination),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.photoScrim),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: FavoriteButton(destination: destination),
        ),
        if (destination.matchScore > 0)
          Positioned(
            top: 12,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "${destination.matchScore} SIGNAL${destination.matchScore == 1 ? "" : "S"} MATCHED",
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ),
        Positioned(
          left: 14,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "FIELD NOTE",
              style: TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
