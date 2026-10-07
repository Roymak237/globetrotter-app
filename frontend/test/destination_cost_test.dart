import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/screens/destination_detail_screen.dart";
import "package:globetrotter/utils/destination_cost.dart";
import "package:provider/provider.dart";

/// Every priced destination used to be shown under "EST. DAILY COST".
///
/// Only four of the 104 records are daily budgets. The rest are one museum
/// admission, one plate of food or one night in a room, and the National
/// Museum's 2000 XAF entry presented as a day's spending understates a day
/// in Yaounde by an order of magnitude. The figure was right; the sentence
/// around it was not, and no test could catch that while the label was a
/// constant.
///
/// These read the shipped data file, because the mismatch lived in the gap
/// between the data and the words printed over it.
List<Map<String, dynamic>> loadDestinations() {
  final file = File("../backend/data/destinations.json");
  if (!file.existsSync()) {
    throw StateError("expected to find ${file.path} beside the backend app");
  }
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

const knownBases = {
  "per_day",
  "per_visit",
  "per_meal",
  "per_night",
  "per_trip",
  "free",
  "none",
};

Destination place(String basis, {num? cost}) => Destination.fromJson({
      "id": "test-place",
      "name": "Yaoundé place",
      "region": "Centre",
      "description": "A place in Yaoundé.",
      "avg_cost_per_day": cost,
      "cost_basis": basis,
      "cost_notes": "Indicative figure.",
    });

Widget detailApp(Destination destination, String language) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(
      key: ObjectKey(destination),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: destination),
        builder: (_) => const DestinationDetailScreen(),
      ),
    ),
  );
}

void main() {
  final destinations = loadDestinations();

  test("every destination says what its price buys", () {
    expect(destinations, isNotEmpty);
    for (final json in destinations) {
      final basis = json["cost_basis"];
      expect(knownBases, contains(basis),
          reason: "${json["id"]} has an unusable cost_basis: $basis");
    }
  });

  test("an unpriced record is never given a paying basis, and vice versa", () {
    for (final json in destinations) {
      final destination = Destination.fromJson(json);
      final basis = destination.costBasis;
      if (!destination.hasCostEstimate) {
        // Nothing to charge for means nothing to describe. "none" exists so
        // the tile can say so rather than printing a bare dash.
        expect(basis, "none",
            reason: "${destination.id} has no price but claims $basis");
      } else if (destination.avgCostPerDay == 0) {
        expect(basis, "free",
            reason: "${destination.id} costs nothing but claims $basis");
      } else {
        expect(basis, isNot(anyOf("none", "free")),
            reason: "${destination.id} costs money but claims $basis");
      }
    }
  });

  test("daily is claimed only where the note describes a day", () {
    final daily =
        destinations.where((j) => j["cost_basis"] == "per_day").toList();
    // This is the assertion the old screen failed. Four records are daily
    // budgets; if that count ever grows it should grow because somebody
    // wrote a daily note, not because a default leaked back in.
    expect(daily, isNotEmpty);
    for (final json in daily) {
      final note = (json["cost_notes"] as String? ?? "").toLowerCase();
      // "daily budget", "daily cost" and "day-pass" all price a day.
      // An admission or a plate of food does not, which is the mislabel
      // this guards against.
      expect(note, matches(RegExp(r"\b(daily|day)\b")),
          reason: "${json["id"]} is labelled per_day but its note "
              "does not describe a day: $note");
    }
    expect(daily.length, lessThan(destinations.length ~/ 2),
        reason: "most destinations are admissions and meals, not day budgets");
  });

  test("cost_basis survives a JSON round trip", () {
    final destination = place("per_visit", cost: 2000);
    expect(destination.costBasis, "per_visit");
    expect(destination.toJson()["cost_basis"], "per_visit");
    expect(Destination.fromJson(destination.toJson()).costBasis, "per_visit");
    // An older record written before the field existed must not be invented
    // into a daily cost on read.
    final legacy = Map<String, dynamic>.from(destination.toJson())
      ..remove("cost_basis");
    expect(Destination.fromJson(legacy).costBasis, isEmpty);
  });

  test("amounts keep their digits and name their currency", () {
    // The old label divided by 1000 and rounded, so 1000 and 1499 both
    // printed as "1k XAF" and 60000 lost its hundreds.
    expect(formatXaf(1000), isNot(formatXaf(1499)));
    expect(formatXaf(2000), "2\u202f000 XAF");
    expect(formatXaf(60000), "60\u202f000 XAF");
    expect(formatXaf(500), "500 XAF");
    for (final amount in [500, 1499, 25000, 60000]) {
      expect(formatXaf(amount), contains("XAF"));
      expect(formatXaf(amount).replaceAll(RegExp(r"[^0-9]"), ""),
          amount.toString());
    }
  });

  testWidgets("the detail tile names the basis instead of assuming a day",
      (tester) async {
    const expected = {
      "per_visit": "ENTRY PER PERSON",
      "per_meal": "MEAL FOR ONE",
      "per_night": "PER NIGHT",
      "per_trip": "ACCESS AND TRANSPORT",
      "per_day": "COST PER DAY",
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(detailApp(place(entry.key, cost: 2000), "en"));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget,
          reason: "${entry.key} should be headed ${entry.value}");
      if (entry.key != "per_day") {
        expect(find.textContaining("DAILY"), findsNothing,
            reason: "${entry.key} is not a daily cost");
      }
      expect(find.textContaining("2\u202f000 XAF"), findsOneWidget);
    }
  });

  testWidgets("a museum admission is never shown as a daily cost in French",
      (tester) async {
    final museum = destinations.firstWhere(
      (j) => j["cost_basis"] == "per_visit" && (j["avg_cost_per_day"] ?? 0) > 0,
    );
    await tester.pumpWidget(detailApp(Destination.fromJson(museum), "fr"));
    await tester.pump();
    expect(find.text("ENTRÉE PAR PERSONNE"), findsOneWidget);
    expect(find.textContaining("JOURNALIER"), findsNothing);
  });

  testWidgets("a free place says so rather than printing a bare zero",
      (tester) async {
    await tester.pumpWidget(detailApp(place("free", cost: 0), "en"));
    await tester.pump();
    expect(find.text("ENTRY"), findsOneWidget);
    expect(find.text("Free"), findsOneWidget);
    expect(find.textContaining("0 XAF"), findsNothing);
  });
}
