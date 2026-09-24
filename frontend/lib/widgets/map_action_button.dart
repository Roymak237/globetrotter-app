import "package:flutter/material.dart";

import "../utils/theme.dart";

class MapActionButton extends StatelessWidget {
  final bool locating;
  final bool hasCurrentLocation;
  final VoidCallback onPressed;

  /// Whether the camera is currently chasing the traveller.
  ///
  /// Following is a mode rather than a one-off action, so the button has to
  /// show which state it is in; otherwise a map that keeps sliding back looks
  /// broken rather than deliberate.
  final bool following;

  final String? semanticLabel;

  const MapActionButton({
    super.key,
    required this.locating,
    required this.hasCurrentLocation,
    required this.onPressed,
    this.following = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final active = following && hasCurrentLocation;
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel ?? "Center map on my current location",
      child: Material(
        color: active ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        shadowColor: AppTheme.primaryDark.withValues(alpha: 0.2),
        child: InkWell(
          onTap: locating ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 48,
            height: 48,
            child: locating
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    active
                        ? Icons.navigation_rounded
                        : Icons.my_location_rounded,
                    color: active
                        ? Colors.white
                        : hasCurrentLocation
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}
