import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/widgets/auth_widgets.dart";
import "package:globetrotter/widgets/looping_video.dart";

/// The animation sits on the sign-in page as its own element.
///
/// It was briefly a full-bleed background behind the form, which put moving
/// video under the username and password fields. These tests pin it to the
/// layout instead: a bounded element above the card, never a backdrop.
Future<void> pumpAnimation(
  WidgetTester tester, {
  Size screen = const Size(400, 900),
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: screen),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: AuthAnimation()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group("The sign-in animation on the page", () {
    testWidgets("occupies a bounded box rather than filling the screen",
        (tester) async {
      await pumpAnimation(tester, screen: const Size(400, 900));

      final box = tester.getSize(find.byType(LoopingVideo));

      expect(box.height, lessThan(900),
          reason: "a full-height element would be a background again");
      expect(box.width, lessThan(400),
          reason: "a full-width element would be a background again");
      expect(box.height, greaterThan(0));
    });

    testWidgets("keeps the source shape so the frame is never cropped",
        (tester) async {
      // The clip is a composed animation, so trimming the frame would cut
      // off whatever it was drawn around.
      await pumpAnimation(tester);

      final box = tester.getSize(find.byType(LoopingVideo));
      expect(box.width / box.height, closeTo(576 / 1024, 0.01));

      final video = tester.widget<LoopingVideo>(find.byType(LoopingVideo));
      expect(video.fit, BoxFit.contain);
    });

    testWidgets("scales with the screen instead of using one fixed size",
        (tester) async {
      await pumpAnimation(tester, screen: const Size(400, 800));
      final short = tester.getSize(find.byType(LoopingVideo)).height;

      await pumpAnimation(tester, screen: const Size(800, 1200));
      final tall = tester.getSize(find.byType(LoopingVideo)).height;

      expect(tall, greaterThan(short));
    });

    testWidgets("stays out of the way on a screen too short for it",
        (tester) async {
      // On a small phone the keyboard and the form already fill the
      // screen; an animation above them would push the fields off.
      await pumpAnimation(tester, screen: const Size(360, 560));

      expect(find.byType(LoopingVideo), findsNothing);
      expect(tester.getSize(find.byType(AuthAnimation)), Size.zero);
    });
  });
}
