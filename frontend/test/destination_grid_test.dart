import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/utils/layout.dart";
import "package:globetrotter/widgets/destination_card.dart";
import "package:globetrotter/widgets/destination_grid.dart";
import "package:globetrotter/widgets/state_views.dart";
import "package:provider/provider.dart";

Destination _destination() => Destination(
      id: "d1",
      name: "Bimbia Slave Trade Departure Point and Heritage Site",
      region: "South-West",
      description: "A coastal heritage site.",
      tags: const ["heritage", "coastal", "history"],
      avgCostPerDay: 25000,
      highlights: const ["Guided tour"],
    );

/// Wraps [child] with everything a DestinationCard needs to build.
///
/// The card embeds a FavoriteButton, which reads FavoritesProvider. Without it
/// the card throws while building and any size assertion below would be
/// measuring a failure rather than a layout.
Widget _app(Widget child) => ChangeNotifierProvider<FavoritesProvider>(
      create: (_) => FavoritesProvider(),
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    );

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(child));
  await tester.pump();
}

/// The height of the artwork in the first card on screen.
///
/// The card is an AspectRatio above a text block, so this is the measurement
/// that the complaint was actually about.
double _firstImageHeight(WidgetTester tester) {
  final finder = find
      .descendant(
        of: find.byType(DestinationCard).first,
        matching: find.byType(AspectRatio),
      )
      .first;
  return tester.getSize(finder).height;
}

Widget _grid({int count = 8}) => CustomScrollView(
      slivers: [
        DestinationCardsSliver(
          itemCount: count,
          itemBuilder: (_, __) => DestinationCard(destination: _destination()),
        ),
      ],
    );

void main() {
  group("Card artwork stays a sensible size", () {
    // The ceiling is set by the widest single tile the breakpoints allow: at
    // 1079px the layout is still two columns, giving a ~507px card and a
    // ~308px image. Anything materially above that means a card is being
    // stretched rather than a column being added.
    const maxImageHeight = 320.0;

    for (final width in [800.0, 1080.0, 1440.0, 1920.0, 2560.0]) {
      testWidgets("image is not oversized at ${width}px", (tester) async {
        await _pump(tester, width, _grid());

        expect(
          _firstImageHeight(tester),
          lessThan(maxImageHeight),
          reason: "the artwork is stretching with the window at ${width}px",
        );
      });
    }

    testWidgets("a phone keeps the full-width card", (tester) async {
      await _pump(tester, 390, _grid());

      // One column is the right answer on a phone; the card is already a
      // comfortable size and a grid would make it cramped.
      expect(AppLayout.columnsFor(390), 1);
      final cardWidth =
          tester.getSize(find.byType(DestinationCard).first).width;
      expect(cardWidth, greaterThan(300));
    });

    testWidgets("a wide window shows several cards per row", (tester) async {
      await _pump(tester, 1920, _grid());

      // The point of the grid is more cards, not bigger ones. At 1920 the
      // breakpoints give four columns, so the first row should hold four.
      final cards = tester.widgetList(find.byType(DestinationCard)).length;
      expect(cards, greaterThanOrEqualTo(4));
    });
  });

  group("The layout this replaced", () {
    testWidgets("a plain full-width list is what made the images huge",
        (tester) async {
      // Documents the bug rather than describing it. This is the layout the
      // recommendations and saved lists used: a ListView of full-width cards.
      // The same card in the same window renders its art nearly four times
      // taller, which is what "big images" meant.
      await _pump(
        tester,
        1920,
        ListView.builder(
          itemCount: 4,
          itemBuilder: (_, __) => DestinationCard(destination: _destination()),
        ),
      );

      final fullWidth = _firstImageHeight(tester);
      expect(fullWidth, greaterThan(1000),
          reason: "if this is no longer huge the comparison below is moot");

      await _pump(tester, 1920, _grid());
      expect(_firstImageHeight(tester), lessThan(fullWidth / 3));
    });
  });

  group("The scroll view these screens now use", () {
    testWidgets("the empty state still renders inside a sliver",
        (tester) async {
      // Both screens moved from ListView to CustomScrollView, so the empty
      // state is now a sliver child rather than a list child. EmptyStateView
      // centres its content, and Center under an unbounded main-axis
      // constraint is exactly the shape that throws if it is wrong. Render it
      // rather than reason about it.
      await _pump(
        tester,
        390,
        const CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: EmptyStateView(
                icon: Icons.favorite_border,
                title: "Nothing saved yet",
                message: "Tap the heart on a place to keep it here.",
              ),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text("Nothing saved yet"), findsOneWidget);
    });
  });
}
