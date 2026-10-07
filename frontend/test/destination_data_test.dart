import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/models/destination.dart";

/// These tests read the shipped data file rather than a fixture.
///
/// The destination pages print `address`, `location_notes` and
/// `location_sources` straight onto the screen. An earlier verification pass
/// wrote its own working notes into those fields, so users opening a park
/// were reading "ID preserved for itinerary references" and "Unverified
/// coordinates removed; no pin." Nothing in the code was wrong, which is why
/// no test caught it: the bug was entirely in the data.
///
/// So the data is what gets checked.
/// Reads a JSON file from the backend data directory.
///
/// Tests run with the frontend directory as the working directory, so the
/// backend sits one level up.
List<Map<String, dynamic>> loadJson(String name) {
  final file = File("../backend/data/$name");
  if (!file.existsSync()) {
    throw StateError("expected to find ${file.path} beside the backend app");
  }
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

void main() {
  final destinations = loadJson("destinations.json");

  test("every destination parses into the model the screens use", () {
    expect(destinations, isNotEmpty);
    for (final json in destinations) {
      expect(() => Destination.fromJson(json), returnsNormally,
          reason: "${json["id"]} should parse");
    }
  });

  test("visitor-facing text is not the reviewer's working notes", () {
    // Phrases from the audit vocabulary. Each one appeared on a real
    // destination page before this was fixed.
    const jargon = [
      "id preserved",
      "legacy listing",
      "legacy label",
      "filename only",
      "filename-only",
      "no pin",
      "unverified",
      "not independently verified",
      "remote image credit is inherited",
      "byte-identical",
      "dataset continuity",
      "provisional",
    ];

    final offences = <String>[];
    for (final json in destinations) {
      // Only the fields the detail screen actually renders.
      for (final field in ["address", "location_notes", "description"]) {
        final value = (json[field] as String? ?? "").toLowerCase();
        for (final phrase in jargon) {
          if (value.contains(phrase)) {
            offences.add("${json["id"]}.$field contains \"$phrase\"");
          }
        }
      }
    }
    expect(offences, isEmpty,
        reason: "these strings are printed to users:\n${offences.join("\n")}");
  });

  test("a pin is labelled as either the venue or its neighbourhood", () {
    // Without this, an area-level pin is indistinguishable from a precise
    // one, which is the failure mode that makes a map dishonest.
    for (final json in destinations) {
      final hasPin = json["latitude"] != null && json["longitude"] != null;
      final precision = json["location_precision"] as String? ?? "";
      if (hasPin) {
        expect(["exact", "area"], contains(precision),
            reason: "${json["id"]} has a pin but no precision label");
      } else {
        expect(precision, isEmpty,
            reason: "${json["id"]} has no pin, so it cannot claim precision");
      }
    }
  });

  test("coordinates fall inside Cameroon", () {
    // Geocoding returned a hangar for a park and a railway station for the
    // capital before those were rejected by hand. A bounds check will not
    // catch a wrong building, but it does catch a wrong country.
    for (final json in destinations) {
      final latitude = (json["latitude"] as num?)?.toDouble();
      final longitude = (json["longitude"] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;
      expect(latitude, inInclusiveRange(1.5, 13.5),
          reason: "${json["id"]} latitude is outside Cameroon");
      expect(longitude, inInclusiveRange(8.0, 16.5),
          reason: "${json["id"]} longitude is outside Cameroon");
    }
  });

  test("a price is either absent or explained", () {
    // The figures are category estimates, not surveyed prices. A number with
    // no stated basis reads as researched fact, so every one carries a
    // sentence saying what it actually is.
    for (final json in destinations) {
      final notes = (json["cost_notes"] as String? ?? "").trim();
      expect(notes, isNotEmpty,
          reason: "${json["id"]} needs to say where its cost came from, "
              "including when there isn't one");
      if (json["avg_cost_per_day"] != null) {
        expect(json["avg_cost_per_day"], isA<num>());
        expect((json["avg_cost_per_day"] as num) >= 0, isTrue,
            reason: "${json["id"]} cannot cost a negative amount");
      }
    }
  });

  test("every referenced image exists on disk", () {
    // A missing asset renders as an empty gradient card, which is what the
    // placeholder screenshots were showing.
    final missing = <String>[];
    for (final json in destinations) {
      final assets = <String>[
        json["image_asset"] as String? ?? "",
        ...List<String>.from(json["additional_image_assets"] ?? const []),
      ].where((asset) => asset.isNotEmpty);
      for (final asset in assets) {
        if (!File("assets/images/$asset").existsSync()) {
          missing.add("${json["id"]} -> $asset");
        }
      }
    }
    expect(missing, isEmpty, reason: missing.join("\n"));
  });

  test("saved itineraries only reference destinations that still exist", () {
    // Itinerary stops are stored as plain id strings with no foreign key, so
    // deleting a destination silently leaves a stop that resolves to nothing.
    final ids = destinations.map((d) => d["id"] as String).toSet();
    final itineraries = loadJson("itineraries.json");

    final dangling = <String>[];
    for (final itinerary in itineraries) {
      for (final stop
          in List<String>.from(itinerary["destinations"] ?? const [])) {
        // Older itineraries store a display name rather than an id. Only the
        // id-shaped ones can be checked.
        if (stop.startsWith("dest-") && !ids.contains(stop)) {
          dangling.add("${itinerary["id"]} -> $stop");
        }
      }
    }
    expect(dangling, isEmpty, reason: dangling.join("\n"));
  });

  test("a pin always says where it came from", () {
    // The nine records with no coordinate exist precisely because nobody
    // could source one. The inverse has to hold too, or the next bulk
    // import can quietly reintroduce guessed pins.
    for (final json in destinations) {
      final hasPin = json["latitude"] != null && json["longitude"] != null;
      if (!hasPin) continue;
      final sources = List<String>.from(json["location_sources"] ?? const []);
      expect(sources.where((s) => s.trim().isNotEmpty), isNotEmpty,
          reason: "${json["id"]} is pinned but cites nothing");
    }
  });

  test("records taken from OpenStreetMap attribute their claims to it", () {
    // OSM tags a chess club as an amusement arcade and hangs a bank's
    // operator tag on the supermarket hosting its ATM. We did not visit
    // these places, so the copy has to attribute the classification rather
    // than assert it, otherwise their mistake becomes our claim.
    final osmObject = RegExp(
      r"openstreetmap\.org/(node|way|relation)/\d+",
      caseSensitive: false,
    );

    final imported = destinations.where((json) {
      final sources = List<String>.from(json["location_sources"] ?? const []);
      return sources.any(osmObject.hasMatch);
    }).toList();

    expect(imported, isNotEmpty,
        reason: "expected the imported OpenStreetMap destinations");

    for (final json in imported) {
      expect(json["description"] as String, contains("OpenStreetMap"),
          reason: "${json["id"]} states OSM's classification as our own");
      expect(json["location_precision"], equals("exact"),
          reason: "${json["id"]} cites one OSM object, so its pin is exact");
    }
  });
}
