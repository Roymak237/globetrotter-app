import "package:flutter/material.dart";

/// Wallpapers for a conversation, and the colours that stay legible on them.
///
/// Two requirements are in tension here. A wallpaper should be personal, and
/// message text has to stay readable on whichever one is chosen. Letting
/// people pick an arbitrary photo satisfies the first and quietly destroys the
/// second: light text on a bright holiday snap is unreadable, and the app has
/// no way to know that happened.
///
/// So the choice is a curated set of dark tints rather than a free-form image.
/// Every preset here is deliberately deep, which keeps a single light text
/// treatment readable across all of them and keeps the conversation on the
/// same near-black page as the rest of the product. That claim is not a matter
/// of taste — [contrastRatio] measures it and a test asserts every author
/// colour clears WCAG AA against every wallpaper.
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

  /// The deepest point of the wallpaper.
  Color get darkestStop {
    var worst = colors.first;
    for (final color in colors) {
      if (color.computeLuminance() < worst.computeLuminance()) worst = color;
    }
    return worst;
  }

  /// The palest point of the wallpaper, used for contrast checks.
  ///
  /// Text can land anywhere on the gradient, so the honest thing to test
  /// against is the extreme that gives the *worst* contrast with light text —
  /// that is the lightest stop, not the flattering dark end.
  Color get lightestStop {
    var worst = colors.first;
    for (final color in colors) {
      if (color.computeLuminance() > worst.computeLuminance()) worst = color;
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
  static const ChatWallpaper charcoal = ChatWallpaper(
    id: "charcoal",
    label: "Charcoal",
    colors: [Color(0xFF0A0A0A), Color(0xFF151515)],
  );

  static const List<ChatWallpaper> presets = [
    charcoal,
    ChatWallpaper(
      id: "slate",
      label: "Slate",
      colors: [Color(0xFF0D1016), Color(0xFF1A1F29)],
    ),
    ChatWallpaper(
      id: "harmattan",
      label: "Harmattan",
      colors: [Color(0xFF0B1118), Color(0xFF16242F)],
    ),
    ChatWallpaper(
      id: "palm",
      label: "Palm",
      colors: [Color(0xFF0A1210), Color(0xFF15231C)],
    ),
    ChatWallpaper(
      id: "hibiscus",
      label: "Hibiscus",
      colors: [Color(0xFF140C10), Color(0xFF26181E)],
    ),
    ChatWallpaper(
      id: "dune",
      label: "Dune",
      colors: [Color(0xFF13100A), Color(0xFF241E14)],
    ),
  ];

  /// Resolve a stored id, falling back to the default.
  ///
  /// An unknown id means storage outlived a preset that was removed or
  /// renamed. Falling back is right; throwing would make a conversation
  /// unopenable over a cosmetic setting.
  static ChatWallpaper byId(String? id) => presets.firstWhere(
        (wallpaper) => wallpaper.id == id,
        orElse: () => charcoal,
      );

  /// Colours used to label who said what.
  ///
  /// Names were previously drawn in the muted secondary grey at 11px, which
  /// is where "the names are not visible" came from: it is the same weight as
  /// the timestamp and recedes into the background at a glance. Giving each
  /// speaker a distinct, saturated colour makes a group conversation readable
  /// at speed, which a single grey cannot do however bright it is.
  ///
  /// Every entry is a light tone chosen to clear AA on all the deep wallpapers
  /// above; see the contrast test. They were deep tones while the wallpapers
  /// were pale, and inverting the wallpapers without inverting these would
  /// have reproduced the original bug exactly.
  static const List<Color> authorColors = [
    Color(0xFF7FB3FF), // blue
    Color(0xFF7FD79C), // green
    Color(0xFFC49BFF), // purple
    Color(0xFFFFA97A), // burnt orange
    Color(0xFF6FD8D8), // teal
    Color(0xFFFF93BE), // magenta
    Color(0xFFC8DB7A), // olive
    Color(0xFFD7AE93), // tan
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
