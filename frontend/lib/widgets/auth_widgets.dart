import "dart:ui";
import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../utils/theme.dart";
import "asset_slideshow.dart";
import "language_switcher.dart";
import "looping_video.dart";

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
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
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
                        child: LanguageSwitcher(),
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

/// The animated mark above the sign-in form.
///
/// The clip is portrait and runs about fourteen seconds. It is shown whole
/// rather than cropped, because it is a composed animation and trimming the
/// frame would cut off whatever it was drawn around.
///
/// It collapses in three cases, each of which would otherwise leave a hole
/// above the form: a screen too short to spare the room, a user who asked
/// for reduced motion, and a device or browser that will not play it. The
/// sign-in form is the point of the screen and never depends on this.
class AuthAnimation extends StatefulWidget {
  /// Below this, the keyboard plus the form already fill the screen.
  static const _minimumScreenHeight = 640.0;

  /// Width over height of the source clip, used to reserve exactly the
  /// space the frame will occupy so nothing jumps when it appears.
  static const _aspectRatio = 576 / 1024;

  final String assetPath;

  const AuthAnimation({
    super.key,
    this.assetPath = "assets/video/login_background.mp4",
  });

  @override
  State<AuthAnimation> createState() => _AuthAnimationState();
}

class _AuthAnimationState extends State<AuthAnimation> {
  bool _unavailable = false;

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();

    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight < AuthAnimation._minimumScreenHeight) {
      return const SizedBox.shrink();
    }

    // A share of the screen rather than a fixed number, so it stays in
    // proportion between a small phone and a tablet.
    final height = (screenHeight * 0.24).clamp(150.0, 260.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: SizedBox(
          height: height,
          width: height * AuthAnimation._aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: LoopingVideo(
              assetPath: widget.assetPath,
              fit: BoxFit.contain,
              onUnavailable: () {
                if (mounted) setState(() => _unavailable = true);
              },
              // Nothing is drawn while the clip loads. A spinner here would
              // promise something the screen does not need.
              child: const SizedBox.shrink(),
            ),
          ),
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
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
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
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppTheme.primaryDark, size: 25),
            ),
            const SizedBox(width: 12),
            Text(
              localizations.brand,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.secondary,
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
                color: AppTheme.textSecondary,
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
          color: const Color(0xFFFFF0F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppTheme.secondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF8A1721),
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
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
