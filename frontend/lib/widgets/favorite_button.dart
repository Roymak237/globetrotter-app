import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../models/destination.dart";
import "../providers/favorites_provider.dart";
import "../utils/theme.dart";

class FavoriteButton extends StatelessWidget {
  final Destination destination;
  final bool filledBackground;

  const FavoriteButton({
    super.key,
    required this.destination,
    this.filledBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<FavoritesProvider, bool>(
      (favorites) => favorites.isFavorite(destination.id),
    );

    return Semantics(
      button: true,
      toggled: isFavorite,
      label: isFavorite
          ? "Remove ${destination.name} from saved places"
          : "Save ${destination.name} to favorites",
      child: Material(
        color: filledBackground
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.transparent,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: isFavorite ? "Remove from saved" : "Save place",
          onPressed: () async {
            await context.read<FavoritesProvider>().toggle(destination.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isFavorite
                        ? "Removed from saved places"
                        : "Saved to your places",
                  ),
                  duration: const Duration(milliseconds: 1400),
                ),
              );
            }
          },
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey(isFavorite),
              color: isFavorite ? AppTheme.secondary : AppTheme.primaryDark,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
