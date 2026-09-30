import "package:flutter/widgets.dart";

/// Width breakpoints and the layout decisions that follow from them.
///
/// The app was built phone-first, where one full-width card per row is right.
/// On a desktop window that same list stretches each card to the full width of
/// the screen, and because the card art is pinned to a 1.65 aspect ratio the
/// image grows with it: on a 1920px window a single photo renders well over a
/// thousand pixels tall. Hence the reported "big images" on Windows.
///
/// These values live here rather than inline so every screen answers the
/// question the same way, and so the thresholds can be asserted in tests.
class AppLayout {
  const AppLayout._();

  /// Phone and small tablet. One column, full bleed.
  static const double compactMax = 700;

  /// Beyond this a third column fits without the cards becoming cramped.
  static const double expandedMin = 1080;

  /// Cards stop growing here. Past this width a wider window earns more
  /// columns rather than larger cards, which is the whole point.
  static const double maxCardWidth = 460;

  /// Long-form content is capped so lines of text stay readable on a wide
  /// monitor instead of running the full width of the glass.
  static const double maxContentWidth = 1240;

  /// Space between grid tiles. The cards carry their own 16px side margin, so
  /// this is deliberately small; the visible gutter is the sum of the two.
  static const double gridSpacing = 4;

  /// How many columns of cards to show at [width].
  static int columnsFor(double width) {
    if (width <= compactMax) return 1;
    if (width < expandedMin) return 2;
    // Keep adding columns on very wide displays rather than letting each one
    // stretch, but never so many that a card falls below a readable width.
    return (width / maxCardWidth).floor().clamp(3, 5);
  }

  /// True when [width] should use the single-column phone layout.
  static bool isCompact(double width) => columnsFor(width) == 1;

  /// Height a [DestinationCard] needs at a given tile [width].
  ///
  /// The card is an image of fixed aspect ratio above a text block whose rows
  /// are all bounded (`maxLines` 2, 1 and 1), so the height is predictable.
  /// The text allowance is scaled by the platform text scale because a larger
  /// accessibility setting grows the block but not the image.
  ///
  /// Grid tiles are a fixed height, so getting this wrong overflows. The
  /// value is covered by a test that renders every breakpoint at several text
  /// scales and asserts nothing overflows.
  static double destinationTileHeight(BuildContext context, double width) {
    // The card insets itself by 16 on each side and 7 top and bottom.
    const horizontalMargin = 32.0;
    const verticalMargin = 14.0;
    const imageAspectRatio = 1.65;

    // 22 + 16 padding, a two-line display title, two single-line rows and the
    // gaps between them, measured at a text scale of 1.
    const textBlock = 152.0;

    final cardWidth = (width - horizontalMargin).clamp(1.0, double.infinity);
    final scaledText = MediaQuery.textScalerOf(context).scale(textBlock);
    return cardWidth / imageAspectRatio + scaledText + verticalMargin;
  }
}
