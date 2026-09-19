import "package:flutter/material.dart";

import "../models/itinerary.dart";
import "../utils/theme.dart";

class ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final VoidCallback? onTap;
  final VoidCallback? onShare;

  const ItineraryCard({
    super.key,
    required this.itinerary,
    this.onTap,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final destinationCount = itinerary.destinations.length;

    return Semantics(
      button: onTap != null,
      label: "${itinerary.title}, $destinationCount destinations",
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      const _TimelineDot(active: true),
                      Container(
                        width: 1,
                        height: 28,
                        color: AppTheme.accent.withValues(alpha: 0.8),
                      ),
                      const _TimelineDot(active: false),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              itinerary.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontFamily: AppTheme.displayFontFamily,
                                    fontSize: 18,
                                  ),
                            ),
                          ),
                          if (onShare != null) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: "Share trip",
                              child: InkResponse(
                                onTap: onShare,
                                radius: 22,
                                containedInkWell: true,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accentSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.ios_share_rounded,
                                    size: 17,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        "${itinerary.startDate}  →  ${itinerary.endDate}",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.primaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "$destinationCount destination${destinationCount == 1 ? "" : "s"}${itinerary.destinations.isEmpty ? "" : "  •  ${itinerary.destinations.join(", ")}"}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  final bool active;

  const _TimelineDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 12 : 9,
      height: active ? 12 : 9,
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : AppTheme.accent,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? AppTheme.primary : AppTheme.accent,
          width: 2,
        ),
      ),
    );
  }
}
