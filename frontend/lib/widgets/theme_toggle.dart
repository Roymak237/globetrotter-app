import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../providers/theme_provider.dart";
import "../utils/theme.dart";

/// Keyboard-focusable, labelled control shared by auth and the home header.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    // Embedded screens may be hosted with an externally managed ThemeData.
    // Only expose the preference control when the host supplies its owner.
    final provider = context.watch<ThemeProvider?>();
    if (provider == null) return const SizedBox.shrink();
    final palette = AppTheme.of(context);
    final french = Localizations.localeOf(context).languageCode == "fr";
    final label = provider.isDark
        ? (french ? "Activer le thème clair" : "Switch to light theme")
        : (french ? "Activer le thème sombre" : "Switch to dark theme");
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: label,
          toggled: !provider.isDark,
          child: IconButton.filledTonal(
            onPressed: provider.toggle,
            style: IconButton.styleFrom(
              backgroundColor: palette.surface,
              foregroundColor: palette.textPrimary,
              minimumSize: const Size(48, 48),
              side: BorderSide(color: palette.border),
            ),
            icon: Icon(provider.isDark ? Icons.light_mode : Icons.dark_mode),
          ),
        ),
      ),
    );
  }
}
