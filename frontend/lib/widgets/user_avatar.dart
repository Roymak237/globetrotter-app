import "package:flutter/material.dart";

import "../utils/media_url.dart";
import "../utils/theme.dart";

/// A profile photo with an initials fallback.
///
/// Avatars appear in five places - the profile header, the chat room list, the
/// member list, comments and the call screen - and every one of them needs the
/// same three behaviours: resolve the stored relative path to something
/// loadable, fall back to initials when there is no photo, and fall back again
/// when there is one but it fails to load. Each site previously did its own
/// partial version of that, so a fix in one did not reach the others.
class UserAvatar extends StatelessWidget {
  /// The stored reference, typically `/api/media/<id>.jpg`. May be empty.
  final String avatarUrl;

  /// Used for the initial when no image is available.
  final String name;

  final double radius;

  /// Defaults to the theme accent; the call screen sits on a dark backdrop and
  /// overrides it.
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.radius = 20,
    this.backgroundColor,
  });

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? "?" : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(avatarUrl);
    final background = backgroundColor ?? AppTheme.accent;

    final fallback = Text(
      _initial,
      style: TextStyle(
        fontFamily: AppTheme.displayFontFamily,
        fontSize: radius * 0.82,
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );

    if (resolved.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: background,
        child: fallback,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: ClipOval(
        child: Image.network(
          resolved,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // A broken or deleted photo must not leave a blank disc where a
          // person's face should be, so failure lands back on the initial.
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
