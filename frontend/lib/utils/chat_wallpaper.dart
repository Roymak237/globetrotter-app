import "package:flutter/material.dart";

/// Wallpapers for a conversation, and the colours that stay legible on them.
///
/// Two requirements are in tension here. A wallpaper should be personal, and
/// message text has to stay readable on whichever one is chosen. Letting
/// people pick an arbitrary photo satisfies the first and quietly destroys the
/// second: dark text on a dark holiday snap is unreadable, and the app has no
/// way to know that happened.
///
/// So the choice is a curated set of light tints rather than a free-form
/// image. Every preset here is deliberately pale, which keeps a single dark
/// text treatment readable across all of them. That claim is not a matter of
/// taste — [contrastRatio] measures it and a test asserts every author colour
/// clears WCAG AA against every wallpaper.
@immutable
class ChatWallpaper {
  /// Stable key written to storage. Renaming a label is safe; renaming this
  /// would silently reset everyone's choice.
  final String id;

  /// Shown in the picker.
  final String label;

  /// Top-left to bottom-right gradient stops.
  final List<Color> colors;

  const ChatWallpaper({
    required this.id,
    required this.label,
    required this.colors,
  });

  /// The palest point of the wallpaper, used for contrast checks.
  ///
  /// Text can land anywhere on the gradient, so the honest thing to test
  /// against is the extreme that gives the *worst* contrast with dark text —
  /// that is the darkest stop, not the lightest.
  Color get darkestStop {
    var worst = colors.first;
    for (final color in colors) {
      if (color.computeLuminance() < worst.computeLuminance()) worst = color;
    }
    return worst;
  }

  BoxDecoration get decoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      );

  /// The default, matching the app background so an unset room looks unchanged.
  static const ChatWallpaper sand = ChatWallpaper(
    id: "sand",
    label: "Sand",
    colors: [Color(0xFFFAF5EE), Color(0xFFF3E8D8)],
  );

  static const List<ChatWallpaper> presets = [
    sand,
    ChatWallpaper(
      id: "dune",
      label: "Dune",
      colors: [Color(0xFFFBF1E3), Color(0xFFF0DCC0)],
    ),
    ChatWallpaper(
      id: "palm",
      label: "Palm",
      colors: [Color(0xFFEFF7F0), Color(0xFFDDEEE1)],
    ),
    ChatWallpaper(
      id: "harmattan",
      label: "Harmattan",
      colors: [Color(0xFFEDF3FA), Color(0xFFDAE7F5)],
    ),
    ChatWallpaper(
      id: "hibiscus",
      label: "Hibiscus",
      colors: [Color(0xFFFBEFEF), Color(0xFFF5DEDE)],
    ),
    ChatWallpaper(
      id: "clay",
      label: "Clay",
      colors: [Color(0xFFFAF0EA), Color(0xFFF2DCCF)],
    ),
  ];

  /// Resolve a stored id, falling back to the default.
  ///
  /// An unknown id means storage outlived a preset that was removed or
  /// renamed. Falling back is right; throwing would make a conversation
  /// unopenable over a cosmetic setting.
  static ChatWallpaper byId(String? id) => presets.firstWhere(
        (wallpaper) => wallpaper.id == id,
        orElse: () => sand,
      );

  /// Colours used to label who said what.
  ///
  /// Names were previously drawn in the muted secondary brown at 11px, which
  /// is where "the names are not visible" came from: it is the same weight as
  /// the timestamp and recedes into the background at a glance. Giving each
  /// speaker a distinct, saturated colour makes a group conversation readable
  /// at speed, which a single grey cannot do however dark it is.
  ///
  /// Every entry is a deep tone chosen to clear AA on all the pale wallpapers
  /// above; see the contrast test.
  static const List<Color> authorColors = [
    Color(0xFF0D47A1), // deep blue
    Color(0xFF1B5E20), // deep green
    Color(0xFF4A148C), // deep purple
    // Material's deep-orange 900 (#BF360C) was the first choice here and
    // measured 4.25 against the warmer wallpapers — under AA. The contrast
    // test caught it; this is the darker tone that clears it.
    Color(0xFF8D2C08), // burnt orange
    Color(0xFF006064), // deep teal
    Color(0xFF880E4F), // deep magenta
    Color(0xFF33691E), // olive
    Color(0xFF3E2723), // dark brown
  ];

  /// A stable colour for [username].
  ///
  /// Deterministic so the same person keeps the same colour between sessions
  /// and across devices; a random pick per build would make the colour noise
  /// rather than information.
  static Color authorColor(String username) {
    if (username.isEmpty) return authorColors.first;
    var hash = 0;
    for (final unit in username.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return authorColors[hash % authorColors.length];
  }

  /// WCAG 2.1 relative contrast between two opaque colours, 1.0 to 21.0.
  ///
  /// Present so the readability claim above can be asserted rather than
  /// asserted-in-a-comment.
  static double contrastRatio(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    final lighter = a > b ? a : b;
    final darker = a > b ? b : a;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
