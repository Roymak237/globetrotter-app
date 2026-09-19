import "package:flutter/material.dart";

import "../utils/theme.dart";

class MapActionButton extends StatelessWidget {
  final bool locating;
  final bool hasCurrentLocation;
  final VoidCallback onPressed;

  const MapActionButton({
    super.key,
    required this.locating,
    required this.hasCurrentLocation,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Center map on my current location",
      child: Material(
        color: AppTheme.surface,
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
                    Icons.my_location_rounded,
                    color: hasCurrentLocation
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
