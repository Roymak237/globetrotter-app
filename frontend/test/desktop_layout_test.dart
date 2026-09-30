import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/utils/layout.dart";
import "package:globetrotter/widgets/destination_card.dart";
import "package:provider/provider.dart";

Destination _destination() => Destination(
      id: "d1",
      // A long name so the title takes its full two lines, which is the worst
      // case for tile height.
      name: "Bimbia Slave Trade Departure Point and Heritage Site",
      region: "South-West",
      description: "A coastal heritage site.",
      tags: const ["heritage", "coastal", "history"],
      avgCostPerDay: 25000,
      highlights: const ["Guided tour"],
    );

/// Render [count] cards in the grid the destinations list uses at [width].
Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  required double textScale,
  int count = 6,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // DestinationCard embeds a FavoriteButton, which reads FavoritesProvider.
    // Without it the card throws while building and the overflow assertion
    // below would fire on an unrelated exception.
    ChangeNotifierProvider<FavoritesProvider>(
      create: (_) => FavoritesProvider(),
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Builder(
                builder: (inner) {
                  final columns = AppLayout.columnsFor(width);
                  if (columns == 1) {
                    return ListView.builder(
                      itemCount: count,
                      itemBuilder: (_, __) =>
                          DestinationCard(destination: _destination()),
                    );
                  }
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AppLayout.gridSpacing,
                      mainAxisSpacing: AppLayout.gridSpacing,
                      mainAxisExtent: AppLayout.destinationTileHeight(
                        inner,
                        width / columns,
                      ),
                    ),
                    itemCount: count,
                    itemBuilder: (_, __) =>
                        DestinationCard(destination: _destination()),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group("Column counts", () {
    // A phone stays single column; anything wider earns more, so that a wide
    // window gets more cards rather than bigger ones.
    test("a phone width gets one column", () {
      expect(AppLayout.columnsFor(390), 1);
      expect(AppLayout.columnsFor(700), 1);
      expect(AppLayout.isCompact(390), isTrue);
    });

    test("a tablet or small window gets two", () {
      expect(AppLayout.columnsFor(701), 2);
      expect(AppLayout.columnsFor(1000), 2);
    });

    test("a desktop window gets at least three", () {
      expect(AppLayout.columnsFor(1080), 3);
      expect(AppLayout.columnsFor(1440), 3);
      expect(AppLayout.columnsFor(1920), 4);
      expect(AppLayout.isCompact(1920), isFalse);
    });

    test("columns are capped so cards never get tiny", () {
      expect(AppLayout.columnsFor(5000), 5);
    });

    // The original complaint: a full-width card on a desktop window renders
    // its 1.65 aspect ratio art over a thousand pixels tall.
    test("a card is never wider than a comfortable reading width", () {
      for (final width in [1080.0, 1440.0, 1920.0, 2560.0]) {
        final cardWidth = width / AppLayout.columnsFor(width);
        expect(
          cardWidth,
          lessThanOrEqualTo(AppLayout.maxCardWidth + 200),
          reason: "a $width window would give ${cardWidth}px cards",
        );
      }
    });
  });

  group("Cards fit their grid tile", () {
    // Grid tiles are a fixed height, so if destinationTileHeight under-counts
    // the text block the card overflows and Flutter paints the yellow stripes.
    // The text block scales with the accessibility text size but the image
    // does not, so both axes are swept here.
    for (final width in [390.0, 800.0, 1100.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.15, 1.3]) {
        testWidgets("no overflow at ${width}px and ${scale}x text",
            (tester) async {
          await _pumpGrid(tester, width: width, textScale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: "a card overflowed its tile at ${width}px / ${scale}x",
          );
        });
      }
    }
  });
}
