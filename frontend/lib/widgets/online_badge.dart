import "package:flutter/material.dart";

/// The green dot that says someone is reachable right now.
///
/// "Reachable" here means exactly one thing: they hold an open signalling
/// socket, which is the same registry the server consults when deciding
/// whether a call can ring at all. Anything looser — last-seen timestamps,
/// recent activity — would show green for someone a call would silently fail
/// to reach, which is the confusion this is meant to remove.
class OnlineDot extends StatelessWidget {
  final bool online;
  final double size;

  /// Colour of the ring drawn around the dot. It exists to keep the dot
  /// visible against whatever sits behind it, so it should match that
  /// background rather than the dot.
  final Color borderColor;

  const OnlineDot({
    super.key,
    required this.online,
    this.size = 11,
    this.borderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (!online) return const SizedBox.shrink();

    return Semantics(
      label: "Online",
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The same green every messenger uses for this. Familiarity is the
          // point; a brand colour here would read as decoration.
          color: const Color(0xFF25D366),
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: size * 0.18),
        ),
      ),
    );
  }
}

/// An avatar, or any other badge target, with an online dot on its corner.
class OnlineBadge extends StatelessWidget {
  final Widget child;
  final bool online;
  final double dotSize;
  final Color borderColor;

  const OnlineBadge({
    super.key,
    required this.child,
    required this.online,
    this.dotSize = 12,
    this.borderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (!online) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -1,
          bottom: -1,
          child: OnlineDot(
            online: true,
            size: dotSize,
            borderColor: borderColor,
          ),
        ),
      ],
    );
  }
}
