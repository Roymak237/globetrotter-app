import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Every destination the app ships has a photograph.
///
/// This was not true for a long time: 50 of 104 records rendered a
/// placeholder because no picture of them existed. Ten independent searches
/// of freely-licensed sources - Wikimedia Commons by coordinate and by text,
/// its Yaounde category tree, OpenStreetMap picture tags, Openverse, Wikidata
/// P18, Panoramax street-level - found nothing for any of them, so they were
/// deleted rather than left showing a blank card.
///
/// That makes "has a photograph" an invariant of the catalogue rather than an
/// aspiration, and invariants should be enforced by something that fails.
/// Without this, the next hand-added record silently reintroduces the blank
/// card and nobody notices until it is on a phone.
///
/// These read the shipped data file and the real asset directory, because the
/// failure mode is a record and a file disagreeing, which no amount of widget
/// testing can see.
List<Map<String, dynamic>> loadDestinations() {
  final file = File("../backend/data/destinations.json");
  if (!file.existsSync()) {
    throw StateError("expected to find ${file.path} beside the backend app");
  }
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

/// Asset folders pubspec.yaml actually bundles. A file present on disk but
/// outside a declared folder is missing at runtime and present at review,
/// which is the worst combination.
Set<String> bundledFolders() {
  // Checked in with CRLF on Windows. Dart keeps the \r that Python's
  // read_text() silently drops, so normalise before matching or the regex
  // quietly returns nothing and every asset looks unbundled.
  final text = File("pubspec.yaml").readAsStringSync().replaceAll("\r\n", "\n");
  final block = RegExp(r"\n  assets:\n((?:\s+[-#].*\n)+)").firstMatch(text);
  if (block == null) {
    // Failing to parse is not the same as finding nothing. Say so, otherwise
    // a broken parser reads as "no asset is bundled".
    throw StateError("could not find the assets: block in pubspec.yaml");
  }
  return block
      .group(1)!
      .split("\n")
      .map((line) => line.trim())
      .where((line) => line.startsWith("- "))
      .map((line) => line.substring(2).trim())
      .toSet();
}

void main() {
  final destinations = loadDestinations();
  final folders = bundledFolders();

  test("the catalogue is not empty", () {
    // Guards every test below: all of them pass trivially over no records.
    expect(destinations.length, greaterThan(50));
  });

  test("every destination has a picture", () {
    // Deliberately stricter than the widget, which will fall back to
    // image_url. A remote URL is a network dependency and a dead link
    // waiting to happen; the promise for the shipped catalogue is a real
    // photograph bundled in assets. All 86 records meet that today.
    final blank = <String>[];
    for (final json in destinations) {
      final asset = (json["image_asset"] as String?) ?? "";
      if (asset.trim().isEmpty) {
        blank.add("${json["id"]} ${json["name"]}");
      }
    }
    expect(blank, isEmpty,
        reason: "no bundled photograph:\n  ${blank.join("\n  ")}");
  });

  test("every named image file is actually on disk", () {
    final missing = <String>[];
    for (final json in destinations) {
      final asset = (json["image_asset"] as String?) ?? "";
      if (asset.isEmpty) continue;
      if (!File("assets/images/$asset").existsSync()) {
        missing.add("${json["id"]} -> $asset");
      }
      for (final extra
          in (json["additional_image_assets"] as List? ?? []).cast<String>()) {
        if (!File("assets/images/$extra").existsSync()) {
          missing.add("${json["id"]} gallery -> $extra");
        }
      }
    }
    expect(missing, isEmpty,
        reason: "named but not present:\n  ${missing.join("\n  ")}");
  });

  test("every image sits in a folder pubspec bundles", () {
    final unbundled = <String>{};
    for (final json in destinations) {
      final asset = (json["image_asset"] as String?) ?? "";
      if (asset.isEmpty) continue;
      final declared = "assets/images/$asset";
      final folder = "${declared.substring(0, declared.lastIndexOf("/"))}/";
      if (!folders.contains(folder) && !folders.contains(declared)) {
        unbundled.add("$asset needs '$folder' in pubspec.yaml");
      }
    }
    expect(unbundled, isEmpty,
        reason:
            "present on disk but not shipped:\n  ${unbundled.join("\n  ")}");
  });

  test("no two destinations claim the same photograph", () {
    // A duplicate means one of them is showing a picture of somewhere else,
    // which is worse than showing nothing.
    final byAsset = <String, List<String>>{};
    for (final json in destinations) {
      final asset = (json["image_asset"] as String?) ?? "";
      if (asset.isEmpty) continue;
      byAsset.putIfAbsent(asset, () => []).add(json["id"] as String);
    }
    final shared = byAsset.entries.where((e) => e.value.length > 1).toList();
    expect(shared, isEmpty,
        reason: shared
            .map((e) => "${e.key} claimed by ${e.value.join(", ")}")
            .join("\n  "));
  });
}
