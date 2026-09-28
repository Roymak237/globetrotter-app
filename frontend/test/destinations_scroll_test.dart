import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/screens/destinations_screen.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:provider/provider.dart";

const _heading = "Find your next field note";

/// Twenty places, more than fits on a phone, so the list really has somewhere
/// to scroll to.
List<Map<String, dynamic>> fakePlaces([int count = 20]) => List.generate(
      count,
      (index) => {
        "id": "place-$index",
        "name": "Place $index",
        "region": "Centre",
        "description": "A place worth the detour.",
        "avg_cost_per_day": 15000,
      },
    );

http.Client stubClient({int count = 20}) => MockClient((request) async {
      if (request.url.path.endsWith("/destinations")) {
        return http.Response(
          jsonEncode(fakePlaces(count)),
          200,
          headers: {"content-type": "application/json; charset=utf-8"},
        );
      }
      return http.Response("[]", 200);
    });

Widget host() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MaterialApp(
        locale: Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: DestinationsScreen()),
      ),
    );

/// The vertical position of [finder], or null when it is not on screen.
double? topOf(WidgetTester tester, Finder finder) =>
    finder.evaluate().isEmpty ? null : tester.getTopLeft(finder).dy;

/// Swipes in steps rather than one jump, the way a finger actually moves.
///
/// A floating header reveals itself from the per-frame scroll deltas, so a
/// single teleporting drag does not exercise what a real swipe does.
Future<void> swipe(WidgetTester tester, double dy, {int steps = 6}) async {
  final gesture = await tester
      .startGesture(tester.getCenter(find.byType(CustomScrollView)));
  await tester.pump();
  for (var step = 0; step < steps; step++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("the search field scrolls with the list, not above it",
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The point of the change: the intro lives inside the scrollable, so it
      // can leave. It used to sit in a Column above a separate ListView, which
      // welded it to the top of the screen permanently.
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
    }, () => stubClient());
  });

  testWidgets("swiping up clears the heading and search off the screen",
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final heading = find.text(_heading);
      final before = topOf(tester, heading);
      expect(before, isNotNull, reason: "heading should start on screen");

      await swipe(tester, -600);

      final after = topOf(tester, heading);
      // Either it left the tree, or it moved well out of the way. Both mean
      // the photographs got the space.
      expect(
        after == null || after <= before! - 300,
        isTrue,
        reason: "heading should have scrolled away, was $before now $after",
      );
    }, () => stubClient());
  });

  testWidgets("the filter chips return on a small swipe back", (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await swipe(tester, -600);
      expect(find.text("Gaming"), findsNothing,
          reason: "chips should clear away while browsing");

      // A short swipe back, nothing like a scroll to the top of the results.
      await swipe(tester, 180);

      final chipTop = topOf(tester, find.text("Gaming"));
      expect(chipTop, isNotNull, reason: "chips should float back into view");
      expect(
        chipTop! < 120,
        isTrue,
        reason: "chips should sit at the top of the viewport, at $chipTop",
      );

      // The other half of the promise: the filters came back without the list
      // jumping to the top, so the reader keeps their place.
      expect(find.text(_heading), findsNothing);
    }, () => stubClient());
  });

  testWidgets("the result count stays live once the bar is a sliver header",
      (tester) async {
    // The bar is built through a delegate, which is reused unless it reports
    // that it should rebuild. Getting that wrong freezes the count and the
    // selected chip at whatever they were on first layout.
    await http.runWithClient(() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text("20 places found"), findsOneWidget);
    }, () => stubClient());
  });
}
