import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Reads the width, height, bit depth and colour type from a PNG header.
///
/// The IHDR chunk always sits at a fixed offset right after the 8-byte
/// signature, so this needs no image library.
({int width, int height, int depth, int colourType}) readPngHeader(File file) {
  final bytes = file.readAsBytesSync();
  final signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) {
      throw StateError("${file.path} is not a PNG");
    }
  }
  int u32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (
    width: u32(16),
    height: u32(20),
    depth: bytes[24],
    colourType: bytes[25],
  );
}

void main() {
  group("App icons", () {
    // Sizes the platforms require. A launcher given the wrong size silently
    // rescales it and the icon goes soft, which is hard to notice in review.
    const expectedSizes = <String, int>{
      "web/icons/Icon-192.png": 192,
      "web/icons/Icon-512.png": 512,
      "web/icons/Icon-maskable-192.png": 192,
      "web/icons/Icon-maskable-512.png": 512,
      "web/favicon.png": 16,
      "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
      "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
      "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
      "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
      "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
      "android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png": 108,
      "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png":
          432,
      "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png":
          1024,
      "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png":
          180,
    };

    expectedSizes.forEach((path, size) {
      test("$path is ${size}x$size", () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: "$path is missing");
        final header = readPngHeader(file);
        expect(header.width, size);
        expect(header.height, size);
      });
    });

    test("iOS icons carry no alpha channel", () {
      // App Store submission rejects app icons with transparency, and the
      // failure arrives at upload time rather than at build time.
      final directory =
          Directory("ios/Runner/Assets.xcassets/AppIcon.appiconset");
      final icons = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith(".png"));
      expect(icons, isNotEmpty);
      for (final icon in icons) {
        final header = readPngHeader(icon);
        // Colour types 4 and 6 are the ones carrying an alpha channel.
        expect(header.colourType, isNot(anyOf(4, 6)),
            reason: "${icon.path} has transparency, which iOS rejects");
      }
    });

    test("the Android adaptive foreground keeps its alpha channel", () {
      // This layer is composited over a separate background colour, so it
      // must be transparent or the launcher shows a solid square.
      final header = readPngHeader(File(
          "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png"));
      expect(header.colourType, anyOf(4, 6),
          reason: "the adaptive foreground needs transparency");
    });

    test("the web manifest matches the app's own colours", () {
      // The icon was previously a navy and neon globe while the app is
      // terracotta on sand. These are the two colours the browser paints
      // around the app before any Dart runs, so a mismatch here is the first
      // thing a user sees.
      final manifest = File("web/manifest.json").readAsStringSync();
      expect(manifest, contains("#B4462A"));
      expect(manifest, contains("#FAF5EE"));
    });

    test("the Android adaptive icon sits on the brand background", () {
      // This colour fills the launcher mask around the artwork. It was
      // #000000, which put a black frame round a warm-sand icon on every
      // Android home screen.
      final colours =
          File("android/app/src/main/res/values/colors.xml").readAsStringSync();
      expect(colours, contains("#FAF5EE"),
          reason: "the adaptive icon background should be the brand sand");
      expect(colours, isNot(contains("#000000")));
    });
  });
}
