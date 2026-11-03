import "dart:ui";
import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../utils/theme.dart";
import "asset_slideshow.dart";
import "language_switcher.dart";
import "theme_toggle.dart";

class AuthBackdrop extends StatelessWidget {
  final Widget child;

  static const _backgroundAssets = [
    "assets/images/tourist/reunifiacation monument.jpg",
    "assets/images/tourist/city council.webp",
    "assets/images/tourist/i love my country cameroon monument.webp",
    "assets/images/shopping/mokolo market.webp",
    "assets/images/tourist/parcour vita playground.png",
    "assets/images/tourist/africa deployments.webp",
    "assets/images/recreational/waza park.webp",
  ];

  const AuthBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF1A0B2E)),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: AssetSlideshow(
                  assetPaths: _backgroundAssets,
                  opacity: 0.75,
                  frameInterval: Duration(seconds: 6),
                  transitionDuration: Duration(milliseconds: 1000),
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppTheme.immersiveScrim),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: child,
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 8,
                        right: 20,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ThemeToggle(),
                            SizedBox(width: 8),
                            LanguageSwitcher(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  final Widget child;
  const AuthFormCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            // The light form is opaque white so photographs cannot muddy ink.
            color: AppTheme.of(context).surface.withValues(
                  alpha: AppTheme.of(context).isDark ? 0.72 : 1,
                ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppTheme.of(context).border),
            boxShadow: [
              BoxShadow(
                color: AppTheme.of(context).shadow.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AuthIntro extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;

  const AuthIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.of(context).primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  Icon(icon, color: AppTheme.of(context).primaryDark, size: 25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                localizations.brand,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.of(context).primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.of(context).secondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: AppTheme.displayFontFamily,
                height: 1.05,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.of(context).textSecondary,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: "Authentication error: $message",
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.of(context).error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.of(context).error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                color: AppTheme.of(context).error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppTheme.of(context).error,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  final String label;

  const AuthDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.of(context).textSecondary,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
