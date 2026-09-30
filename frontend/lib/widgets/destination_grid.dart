import "package:flutter/material.dart";

import "../utils/layout.dart";

/// Lays out destination cards as one column on a phone and a grid on anything
/// wider.
///
/// [DestinationCard] pins its artwork to a 1.65 aspect ratio, so a full-width
/// card grows its image with the window: on a 1920px display a single photo
/// renders over a thousand pixels tall and one card fills the screen. The
/// destinations list already solved this, but it did so inline, so the
/// recommendations and saved lists kept the original full-width layout and the
/// oversized images came back on two of the three screens that show these
/// cards.
///
/// The logic lives here so there is one answer rather than three copies that
/// drift apart.
///
/// Emits a sliver, which is what lets a caller put a header above it in the
/// same scroll view without nesting scrollables.
class DestinationCardsSliver extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const DestinationCardsSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = AppLayout.columnsFor(width);

          // A phone keeps the full-bleed list: the card is already a
          // comfortable size there, and a fixed tile height would be a
          // needless constraint.
          if (columns == 1) {
            return SliverList.builder(
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            );
          }

          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppLayout.gridSpacing,
              mainAxisSpacing: AppLayout.gridSpacing,
              // Grid tiles are a fixed height, so this has to account for the
              // text block at the current accessibility text scale as well as
              // the image. Covered by desktop_layout_test.
              mainAxisExtent: AppLayout.destinationTileHeight(
                context,
                width / columns,
              ),
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          );
        },
      );
}
