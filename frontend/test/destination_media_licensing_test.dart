import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/utils/destination_media.dart";

/// Reads the destination records straight off disk.
///
/// The backend serves this file at runtime, but the licence obligations it
/// records are a build-time property of what we ship. Reading it here lets
/// the suite fail before a mis-credited photo reaches a store listing.
List<Map<String, dynamic>> loadDestinations() {
  final file = File("../backend/data/destinations.json");
  if (!file.existsSync()) {
    throw StateError("destinations.json not found at ${file.absolute.path}");
  }
  final decoded = jsonDecode(file.readAsStringSync());
  final records = decoded is List ? decoded : decoded["destinations"] as List;
  return records.cast<Map<String, dynamic>>();
}

/// A credit line has to name somebody and name a licence to be worth
/// anything. "Unknown author" is permitted because Commons genuinely does
/// not record an artist for some older uploads, and saying so is honest.
/// A bare empty string is not.
final _licencePattern = RegExp(
  r"(CC0|CC BY|CC-BY|Public domain|PD)",
  caseSensitive: false,
);

void main() {
  group("Every bundled destination photo can be accounted for", () {
    test("the fallback map credits an author and a licence for every entry",
        () {
      expect(verifiedDestinationMedia, isNotEmpty);

      for (final entry in verifiedDestinationMedia.entries) {
        final media = entry.value;
        expect(
          media.attribution.trim(),
          isNotEmpty,
          reason: "${entry.key} has no attribution at all",
        );
        expect(
          media.attribution.toLowerCase(),
          isNot(contains("unverified")),
          reason:
              "${entry.key} is offered as a verified fallback while admitting "
              "its licence is unverified. One of the two is wrong.",
        );
        expect(
          _licencePattern.hasMatch(media.attribution),
          isTrue,
          reason:
              "${entry.key} names no reusable licence: ${media.attribution}",
        );
      }
    });

    test("fallback URLs are https and point at Wikimedia", () {
      for (final entry in verifiedDestinationMedia.entries) {
        final uri = Uri.tryParse(entry.value.url);
        expect(uri, isNotNull, reason: "${entry.key} has an unparseable URL");
        expect(
          uri!.scheme,
          "https",
          reason: "${entry.key} would be fetched over plaintext",
        );
        expect(
          uri.host.endsWith("wikimedia.org"),
          isTrue,
          reason: "${entry.key} points at ${uri.host}, which is not the source "
              "its credit claims",
        );
      }
    });

    test("fallback URLs carry no analytics parameters", () {
      for (final entry in verifiedDestinationMedia.entries) {
        final uri = Uri.parse(entry.value.url);
        final tracking = uri.queryParameters.keys
            .where((key) => key.toLowerCase().startsWith("utm_"))
            .toList();
        expect(
          tracking,
          isEmpty,
          reason: "${entry.key} would report every fallback fetch to campaign "
              "tracking on the user's behalf: $tracking",
        );
      }
    });

    test("every fallback id refers to a destination that still exists", () {
      final ids = loadDestinations().map((r) => r["id"] as String).toSet();

      for (final key in verifiedDestinationMedia.keys) {
        expect(
          ids,
          contains(key),
          reason:
              "The fallback map holds $key, but no destination has that id. "
              "It can never be reached and will quietly rot.",
        );
      }
    });

    test("every named local photo exists and sits in a declared folder", () {
      // AssetManifest.json is not built for unit tests, and reaching for it
      // only proved that. Checking pubspec against the filesystem tests the
      // same obligation against the two things that actually decide it.
      final pubspec = File("pubspec.yaml").readAsStringSync();
      final declared = RegExp(r"^\s*-\s+(assets/[^\s#]+/)\s*$", multiLine: true)
          .allMatches(pubspec)
          .map((match) => match.group(1)!)
          .toSet();

      final missingFile = <String>[];
      final undeclared = <String>[];

      for (final record in loadDestinations()) {
        final asset = (record["image_asset"] as String? ?? "").trim();
        if (asset.isEmpty) continue;

        final file = File("assets/images/$asset");
        if (!file.existsSync()) {
          missingFile.add("${record["id"]} -> $asset");
          continue;
        }

        final folder =
            "assets/images/${asset.substring(0, asset.lastIndexOf('/') + 1)}";
        if (!declared.contains(folder)) {
          undeclared.add("${record["id"]} -> $folder");
        }
      }

      expect(
        missingFile,
        isEmpty,
        reason:
            "These records name a photo that is not on disk, so the app falls "
            "through to the network every time: $missingFile",
      );
      expect(
        undeclared,
        isEmpty,
        reason:
            "These photos exist but their folder is not listed under assets: "
            "in pubspec.yaml, so Flutter will not bundle them: $undeclared",
      );
    });

    test("a record that names a local photo also records who took it", () {
      final unaccounted = <String>[];
      for (final record in loadDestinations()) {
        final asset = (record["image_asset"] as String? ?? "").trim();
        final credit = (record["image_attribution"] as String? ?? "").trim();
        if (asset.startsWith("destinations/") && credit.isEmpty) {
          unaccounted.add(record["id"] as String);
        }
      }

      expect(
        unaccounted,
        isEmpty,
        reason: "Photos fetched into assets/images/destinations/ come from "
            "Wikimedia under licences that require credit. These carry none: "
            "$unaccounted",
      );
    });
  });
}
