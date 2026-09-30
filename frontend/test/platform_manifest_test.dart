@TestOn("vm")
library;

import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Checks on the platform manifests.
///
/// These are the settings no widget test can reach and no debug run can
/// falsify. Flutter injects some permissions into the generated debug and
/// profile manifests for its own tooling, so a missing declaration in the main
/// manifest behaves perfectly under `flutter run` and only fails once someone
/// installs the release APK. That is the worst possible time to find out, so
/// the manifest is asserted here instead.
void main() {
  final androidManifest =
      File("android/app/src/main/AndroidManifest.xml").readAsStringSync();

  group("Android main manifest", () {
    test(
        "declares INTERNET, without which the release APK cannot reach the API",
        () {
      // Android refuses DNS resolution when this is absent and surfaces it as
      // "Failed host lookup ... errno = 7", which looks like a dead domain
      // rather than a missing permission.
      expect(
        androidManifest,
        contains('android:name="android.permission.INTERNET"'),
        reason: "the release APK has no network access without this",
      );
    });

    test("declares the location permissions the tracker needs", () {
      expect(
        androidManifest,
        contains('android:name="android.permission.ACCESS_FINE_LOCATION"'),
      );
      expect(
        androidManifest,
        contains('android:name="android.permission.ACCESS_COARSE_LOCATION"'),
      );
    });

    test("declares the call permissions", () {
      for (final permission in [
        "android.permission.RECORD_AUDIO",
        "android.permission.CAMERA",
        "android.permission.ACCESS_NETWORK_STATE",
      ]) {
        expect(androidManifest, contains('android:name="$permission"'));
      }
    });

    test("leaves no unresolved manifest placeholder", () {
      // A placeholder with no matching entry in build.gradle.kts fails the
      // Android build rather than the Dart one, so it would not show up in
      // flutter analyze.
      final gradle = File("android/app/build.gradle.kts").readAsStringSync();
      final placeholders = RegExp(r"\$\{([A-Z_]+)\}")
          .allMatches(androidManifest)
          .map((match) => match.group(1)!)
          .toSet();

      for (final placeholder in placeholders) {
        expect(
          gradle,
          contains('manifestPlaceholders["$placeholder"]'),
          reason: "$placeholder is used in the manifest but never defined",
        );
      }
    });

    test("carries no Google Maps key", () {
      // The app renders OpenStreetMap tiles on every platform and has no
      // google_maps_flutter dependency. A key here would be dead config, and
      // a committed credential.
      expect(
          androidManifest, isNot(contains("com.google.android.geo.API_KEY")));
      expect(
        File("android/app/build.gradle.kts").readAsStringSync(),
        isNot(contains("AIza")),
        reason: "an API key should never be hardcoded in the build file",
      );
    });
  });

  group("iOS Info.plist", () {
    test("explains why the app wants the user's location", () {
      // iOS terminates the app outright if it asks for location without a
      // usage string.
      expect(
        File("ios/Runner/Info.plist").readAsStringSync(),
        contains("NSLocationWhenInUseUsageDescription"),
      );
    });

    test("has no Google Maps scaffolding left", () {
      // There is no Podfile and no google_maps_flutter dependency, so the
      // GoogleMaps SDK is not available to link against. An `import
      // GoogleMaps` in AppDelegate would not compile, and the key it read
      // from Info.plist was dead config either way.
      final appDelegate =
          File("ios/Runner/AppDelegate.swift").readAsStringSync();
      expect(appDelegate, isNot(contains("import GoogleMaps")));
      expect(appDelegate, isNot(contains("GMSServices")));
    });
  });

  // This sweep is deliberately broad. An earlier version of this file checked
  // only the two Android files for a hardcoded key, which is why a copy of the
  // same key sat undetected in ios/Runner/Info.plist: the assertion was right
  // but its scope was too narrow. Anything Google-issued starts with "AIza",
  // so every platform config file is scanned rather than an enumerated few.
  group("No committed credentials", () {
    final configFiles = [
      "android/app/src/main/AndroidManifest.xml",
      "android/app/build.gradle.kts",
      "android/build.gradle.kts",
      "ios/Runner/Info.plist",
      "ios/Runner/AppDelegate.swift",
      "ios/Flutter/Debug.xcconfig",
      "ios/Flutter/Release.xcconfig",
      "web/index.html",
      "web/manifest.json",
      "pubspec.yaml",
    ];

    for (final path in configFiles) {
      test("$path holds no API key", () {
        final file = File(path);
        if (!file.existsSync()) return;
        expect(
          file.readAsStringSync(),
          isNot(contains("AIza")),
          reason: "$path appears to contain a Google API key. Remove it, and "
              "revoke the key: deleting it here does not remove it from git "
              "history.",
        );
      });
    }
  });
}
