import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/widgets/destination_image.dart";

/// Fifty of the hundred-odd destinations have no photograph, and none is
/// coming: Wikimedia Commons holds nothing of a cyber cafe in Biyem-Assi,
/// and a sweep of its entire Yaounde inventory offered a power station for
/// a church and a stadium for a dessert shop purely on shared words.
///
/// So the card without a photo is a permanent state, not a loading one. It
/// has to look deliberate, and it must never imply we know what the place
/// looks like.
Destination make({
  required String name,
  List<String> tags = const ["dining"],
  String asset = "",
  String url = "",
}) {
  return Destination.fromJson({
    "id": "test-${name.hashCode}",
    "name": name,
    "region": "Centre",
    "description": "A place used by this test.",
    "tags": tags,
    "avg_cost_per_day": null,
    "highlights": const [],
    "image_url": url,
    "image_asset": asset,
    "image_attribution": "",
    "address": "Yaounde",
    "location_notes": "",
    "location_sources": const [],
    "additional_image_assets": const [],
    "latitude": 3.87,
    "longitude": 11.52,
    "location_precision": "exact",
    "cost_notes": "No price recorded.",
  });
}

Future<void> pump(WidgetTester tester, Destination destination) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 200,
        child: DestinationImage(destination: destination),
      ),
    ),
  ));
}

void main() {
  group("A destination with no photograph", () {
    testWidgets("says so to a screen reader rather than staying silent",
        (tester) async {
      await pump(tester, make(name: "Karoka BBQ service"));

      expect(
        find.bySemanticsLabel("No photograph available for Karoka BBQ service"),
        findsOneWidget,
      );
    });

    testWidgets("is marked with an icon matching what the place is",
        (tester) async {
      // A restaurant under a landscape icon reads as broken. Under a
      // restaurant icon it reads as a place we have no picture of.
      await pump(tester, make(name: "Jodi Bites", tags: ["dining"]));
      expect(find.byIcon(Icons.restaurant_outlined), findsWidgets);

      await pump(tester, make(name: "YSEM", tags: ["education"]));
      expect(find.byIcon(Icons.school_outlined), findsWidgets);

      await pump(tester, make(name: "Rosy Fitness", tags: ["recreation"]));
      expect(find.byIcon(Icons.sports_soccer_outlined), findsWidgets);
    });

    testWidgets(
        "does not fall back to a generic landscape for the "
        "categories we actually ship", (tester) async {
      // Every category the browse screen filters on needs its own glyph,
      // or the fallback silently swallows a whole tab.
      const shipped = [
        "dining",
        "gaming",
        "tourist",
        "leisure",
        "recreation",
        "shopping",
        "education",
        "relaxation",
        "hiking",
        "landmark",
        "family",
      ];
      for (final tag in shipped) {
        await pump(tester, make(name: "Somewhere", tags: [tag]));
        expect(
          find.byIcon(Icons.landscape_outlined),
          findsNothing,
          reason: "$tag has no icon of its own",
        );
      }
    });

    testWidgets(
        "colours the card by category so a grid is not fifty "
        "identical tiles", (tester) async {
      Future<List<Color>> tonesFor(String tag) async {
        await pump(tester, make(name: "Somewhere", tags: [tag]));
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(DestinationImage),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final gradient =
            (box.decoration as BoxDecoration).gradient! as LinearGradient;
        return gradient.colors;
      }

      final dining = await tonesFor("dining");
      final education = await tonesFor("education");
      final landmark = await tonesFor("landmark");

      expect(dining, isNot(equals(education)));
      expect(education, isNot(equals(landmark)));
      expect(dining, isNot(equals(landmark)));
    });

    testWidgets("never shows a photograph borrowed from somewhere else",
        (tester) async {
      await pump(tester, make(name: "Le Premium"));

      // No Image widget at all: not an asset, not a network fetch. The
      // card is drawn, not sourced.
      expect(find.byType(Image), findsNothing);
    });
  });

  group("The shipped data", () {
    test("still has no record carrying a photo it cannot credit", () {
      final file = File("../backend/data/destinations.json");
      final records = (jsonDecode(file.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

      final uncredited = <String>[];
      for (final record in records) {
        final hasPhoto = (record["image_asset"] as String? ?? "").isNotEmpty ||
            (record["image_url"] as String? ?? "").isNotEmpty;
        if (!hasPhoto) continue;
        final credit = (record["image_attribution"] as String? ?? "").trim();
        if (credit.isEmpty) uncredited.add(record["id"] as String);
      }
      expect(uncredited, isEmpty,
          reason: "a shipped photo with no credit line: $uncredited");
    });
  });
}
