import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/utils/theme.dart";

/// The chat room showed a white bar behind white text, which is text you
/// cannot read.
///
/// The app bar sets `foregroundColor: Colors.white` and `backgroundColor:
/// Colors.transparent`, leaning entirely on `flexibleSpace` to paint the
/// brand gradient. That is a fragile arrangement: if the gradient fails to
/// paint for any reason the bar falls back to whatever is behind it, and
/// white-on-white is the result.
///
/// Asserting the widget is in the tree would prove nothing - a DecoratedBox
/// laid out at zero height is still in the tree. So this rasterises the bar
/// and reads the pixels back.
///
/// `toByteData` does real async work, which the fake clock inside
/// `testWidgets` would otherwise block forever; hence `runAsync`.

const int kWidth = 800;
const int kHeight = 600;

/// Colour of one pixel in a raw RGBA buffer.
Color pixelAt(ByteData data, int x, int y) {
  final offset = (y * kWidth + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

/// WCAG relative luminance. sRGB has to be linearised first; averaging the
/// raw channels gives a number that looks plausible and ranks colours wrong.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Contrast ratio of white against [background], per WCAG 2.1.
///
/// The floors that matter here: 3.0 for icons and large text, 4.5 for body
/// text. The app bar title is 21px bold, which WCAG counts as large.
double whiteContrast(Color background) =>
    1.05 / (_relativeLuminance(background) + 0.05);

/// Everything drawn on an app bar in this product is white, and icons are
/// non-text UI components, so 3:1 is the governing requirement.
const double kIconFloor = 3.0;

/// Renders [bar] as a Scaffold app bar and returns the raw RGBA pixels.
Future<ByteData> pumpBar(WidgetTester tester, PreferredSizeWidget bar) async {
  tester.view.physicalSize = const Size(kWidth * 1.0, kHeight * 1.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(appBar: bar, body: const SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  ByteData? data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  return data!;
}

/// Samples a row across the toolbar, skipping the outer edges.
List<Color> sampleRow(ByteData data, int y) {
  final out = <Color>[];
  for (var x = 20; x < kWidth - 20; x += 40) {
    out.add(pixelAt(data, x, y));
  }
  return out;
}

void main() {
  group("The chat app bar", () {
    testWidgets("is dark enough for white text to read", (tester) async {
      final data = await pumpBar(
        tester,
        AppBar(
          title: const Text("caleb"),
          flexibleSpace: AppTheme.appBarBackground,
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
        ),
      );

      final samples = sampleRow(data, 40);
      for (final c in samples) {
        expect(c.a, greaterThan(0.99), reason: "bar pixel $c is see-through");
      }

      final worst =
          samples.map(whiteContrast).reduce((a, b) => a < b ? a : b);
      expect(
        worst,
        greaterThanOrEqualTo(kIconFloor),
        reason: "the weakest point of the bar carries white at only "
            "${worst.toStringAsFixed(2)}:1, under the WCAG $kIconFloor:1 "
            "floor for icons and large text",
      );
    });

    testWidgets("paints the gradient, not one flat colour", (tester) async {
      final data = await pumpBar(
        tester,
        AppBar(
          title: const Text("caleb"),
          flexibleSpace: AppTheme.appBarBackground,
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
        ),
      );

      final left = pixelAt(data, 30, 40);
      final right = pixelAt(data, kWidth - 30, 40);
      final delta = (left.r - right.r).abs() +
          (left.g - right.g).abs() +
          (left.b - right.b).abs();

      // brandGradientHorizontal runs primaryDark -> secondary, so the ends
      // must differ. Equal ends means flexibleSpace painted nothing and we
      // read the same fallback colour twice.
      expect(
        delta,
        greaterThan(0.08),
        reason: "left $left and right $right match, so the gradient is "
            "not painting",
      );
    });

    testWidgets("is still legible without flexibleSpace", (tester) async {
      // A screen that forgets flexibleSpace must not end up white-on-white,
      // so AppBarTheme.backgroundColor has to carry it alone.
      final data = await pumpBar(tester, AppBar(title: const Text("caleb")));
      final c = pixelAt(data, 400, 40);
      expect(
        whiteContrast(c),
        greaterThanOrEqualTo(kIconFloor),
        reason: "a bare AppBar painted $c, carrying white at only "
            "${whiteContrast(c).toStringAsFixed(2)}:1",
      );
    });
  });
}
