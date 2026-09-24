import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../utils/theme.dart";

/// A short, honest profile of the person behind the app, reachable from the
/// Community section of the profile screen.
///
/// Everything stated here is drawn from the repository itself rather than
/// written from memory, so the credits stay true as the project changes.
class AboutDeveloperScreen extends StatelessWidget {
  const AboutDeveloperScreen({super.key});

  /// Kept next to the copy it describes. The stack is deliberately listed in
  /// the order a request travels through it — interface, service, delivery —
  /// so the list reads as an explanation and not just a pile of logos.
  static const List<_Tool> _stack = [
    _Tool(Icons.phone_iphone_rounded, "Flutter"),
    _Tool(Icons.code_rounded, "Dart"),
    _Tool(Icons.dns_rounded, "Python"),
    _Tool(Icons.api_rounded, "Flask"),
    _Tool(Icons.videocam_rounded, "WebRTC"),
    _Tool(Icons.inventory_2_rounded, "Docker"),
    _Tool(Icons.lan_rounded, "Nginx"),
    _Tool(Icons.build_circle_rounded, "Jenkins"),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(t.aboutDeveloperTitle),
        flexibleSpace: AppTheme.appBarBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
        children: [
          const _DeveloperHero(),
          const SizedBox(height: 18),
          _Section(
            icon: Icons.person_outline_rounded,
            title: t.aboutDeveloperWhoTitle,
            child: Text(
              t.aboutDeveloperWhoBody,
              style: const TextStyle(
                height: 1.55,
                fontSize: 14.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            icon: Icons.school_outlined,
            title: t.aboutDeveloperEducationTitle,
            child: Column(
              children: [
                _Fact(
                  label: t.aboutDeveloperSchoolLabel,
                  value: t.aboutDeveloperSchoolValue,
                ),
                const Divider(height: 22),
                _Fact(
                  label: t.aboutDeveloperProgrammeLabel,
                  value: t.aboutDeveloperProgrammeValue,
                ),
                const Divider(height: 22),
                _Fact(
                  label: t.aboutDeveloperStatusLabel,
                  value: t.aboutDeveloperStatusValue,
                  // The only live fact on the page, so it gets the one accent
                  // that signals "ongoing" rather than "recorded".
                  highlight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            icon: Icons.travel_explore_rounded,
            title: t.aboutDeveloperAppTitle,
            child: Text(
              t.aboutDeveloperAppBody,
              style: const TextStyle(
                height: 1.55,
                fontSize: 14.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            icon: Icons.layers_outlined,
            title: t.aboutDeveloperStackTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.aboutDeveloperStackBody,
                  style: const TextStyle(
                    height: 1.55,
                    fontSize: 14.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tool in _stack) _ToolChip(tool: tool),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

/// The gradient card at the top: portrait, name, and the one-line description
/// of the role. Uses the brand gradient so the page opens as part of the
/// product rather than as a plain settings sheet.
class _DeveloperHero extends StatelessWidget {
  const _DeveloperHero();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const ClipOval(
              child: SizedBox(
                width: 116,
                height: 116,
                child: _Portrait(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            t.aboutDeveloperName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTheme.displayFontFamily,
              fontSize: 23,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.aboutDeveloperRole,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 15,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  t.aboutDeveloperLocation,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The portrait, with a monogram fallback. An asset can go missing from a
/// trimmed build long before anyone notices, and a broken image inside a
/// circle is far uglier than initials.
class _Portrait extends StatelessWidget {
  const _Portrait();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      "assets/developer.jpg",
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: AppTheme.primarySoft,
        child: Center(
          child: Text(
            "FN",
            style: TextStyle(
              fontFamily: AppTheme.displayFontFamily,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// White card matching the settings surfaces used on the profile screen, so
/// this page feels like part of the same section it is opened from.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppTheme.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// A label above its value. Stacked rather than side by side because the
/// French and Pidgin labels are long enough to crowd a two-column row on a
/// narrow phone.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (highlight) ...[
          const SizedBox(width: 12),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).aboutDeveloperOngoing,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tool.icon, size: 15, color: AppTheme.primaryDark),
          const SizedBox(width: 7),
          Text(
            tool.label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Closing line and build number. Useful beyond decoration: when someone
/// reports a problem, this is the screen you can ask them to read out.
class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Column(
      children: [
        Text(
          t.aboutDeveloperThanks,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.displayFontFamily,
            fontSize: 14,
            height: 1.5,
            fontStyle: FontStyle.italic,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          t.aboutDeveloperVersion,
          style: const TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
