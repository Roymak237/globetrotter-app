import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/utils/chat_wallpaper.dart";
import "package:globetrotter/utils/theme.dart";

void main() {
  for (final brightness in Brightness.values) {
    test("${brightness.name} semantic foregrounds meet WCAG AA", () {
      final palette = AppPalette(brightness);
      final theme = brightness == Brightness.light
          ? AppTheme.lightTheme
          : AppTheme.darkTheme;
      expect(theme.brightness, brightness);
      expect(theme.scaffoldBackgroundColor, palette.background);
      expect(theme.canvasColor, palette.surface);
      expect(theme.inputDecorationTheme.fillColor, palette.surface);
      expect(theme.dialogTheme.backgroundColor, palette.surface);
      expect(theme.bottomSheetTheme.backgroundColor, palette.surface);
      for (final surface in [
        palette.background,
        palette.surface,
        palette.surfaceSunken,
        palette.primarySoft,
        palette.accentSoft,
        palette.indigoSoft
      ]) {
        for (final ink in [
          palette.textPrimary,
          palette.textSecondary,
          palette.primary
        ]) {
          expect(ChatWallpaper.contrastRatio(ink, surface),
              greaterThanOrEqualTo(4.5));
        }
      }
      for (final fill in [
        palette.primary,
        palette.secondary,
        palette.error,
        palette.indigo
      ]) {
        expect(ChatWallpaper.contrastRatio(palette.onPrimary, fill),
            greaterThanOrEqualTo(4.5));
      }
      expect(
          ChatWallpaper.contrastRatio(palette.primaryDark, palette.primarySoft),
          greaterThanOrEqualTo(4.5));
      expect(ChatWallpaper.contrastRatio(palette.accent, palette.accentSoft),
          greaterThanOrEqualTo(4.5));
    });
  }

  test("light is white, dark retains the shipped near-black palette", () {
    expect(AppTheme.lightTheme.scaffoldBackgroundColor, Colors.white);
    expect(AppTheme.lightTheme.colorScheme.surface, Colors.white);
    expect(AppTheme.darkTheme.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
    expect(AppTheme.darkTheme.colorScheme.surface, const Color(0xFF141414));
  });

  test("fixed brand gradients retain readable white overlays in both modes",
      () {
    for (final gradient in [
      AppTheme.brandGradient,
      AppTheme.brandGradientHorizontal
    ]) {
      for (final stop in gradient.colors) {
        expect(ChatWallpaper.contrastRatio(Colors.white, stop),
            greaterThanOrEqualTo(4.5));
      }
    }
    expect(AppTheme.photoScrim.colors.last, const Color(0xB3060606));
  });

  test("all light wallpapers and author colors retain readable contrast", () {
    for (final wallpaper in ChatWallpaper.presets) {
      final colors = wallpaper.decorationFor(Brightness.light).gradient!.colors;
      for (var i = 0; i < 32; i++) {
        final color = ChatWallpaper.authorColor("author-$i",
            brightness: Brightness.light);
        for (final background in colors) {
          expect(ChatWallpaper.contrastRatio(color, background),
              greaterThanOrEqualTo(4.5));
        }
      }
    }
    expect(
        ChatWallpaper.charcoal.decorationFor(Brightness.light).gradient!.colors,
        [Colors.white, Colors.white]);
  });

  test("empty-chat text clears AA on every wallpaper in both modes", () {
    for (final brightness in Brightness.values) {
      final palette = AppPalette(brightness);
      for (final wallpaper in ChatWallpaper.presets) {
        for (final stop
            in wallpaper.decorationFor(brightness).gradient!.colors) {
          for (final ink in [
            palette.textPrimary,
            palette.textSecondary,
            palette.primary
          ]) {
            expect(ChatWallpaper.contrastRatio(ink, stop),
                greaterThanOrEqualTo(4.5),
                reason: "${brightness.name}/${wallpaper.id}");
          }
        }
      }
    }
  });

  test("UI cannot regress to static dark semantic tokens outside fixed artwork",
      () {
    final pattern = RegExp(
        r"AppTheme\.(background|surface|surfaceSunken|border|textPrimary|textSecondary|primary|onPrimary|primaryDark|secondary|accent|primarySoft|accentSoft|indigo|indigoSoft|error|success|shadow)\b");
    // Fixed photograph/gradient overlays and illustrative photo placeholders.
    const exceptions = {
      "destination_detail_screen.dart": {"accent"},
      "itinerary_detail_screen.dart": {"accent"},
      "destination_card.dart": {"accent", "onPrimary"},
      "destination_image.dart": {"primarySoft", "background"},
    };
    for (final folder in ["lib/screens", "lib/widgets"]) {
      for (final file in Directory(folder).listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith(".dart") || name == "call_screen.dart") continue;
        for (final match in pattern.allMatches(file.readAsStringSync())) {
          expect(exceptions[name]?.contains(match.group(1)) ?? false, isTrue,
              reason: "$name must resolve ${match.group(0)} from its context");
        }
      }
    }
  });
}
