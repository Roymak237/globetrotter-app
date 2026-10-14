import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/utils/chat_wallpaper.dart";
import "package:globetrotter/widgets/online_badge.dart";

void main() {
  group("Wallpapers keep text readable", () {
    // WCAG AA for body text. A wallpaper that pushes a name below this is not
    // a style choice, it is the "names are not visible" bug with extra steps.
    const aa = 4.5;

    test("every author colour clears AA on every wallpaper", () {
      final failures = <String>[];

      for (final wallpaper in ChatWallpaper.presets) {
        for (final color in ChatWallpaper.authorColors) {
          // The lightest stop is the worst case for light text, so that is
          // what gets measured rather than the flattering end of the gradient.
          final ratio =
              ChatWallpaper.contrastRatio(color, wallpaper.lightestStop);
          if (ratio < aa) {
            failures.add(
              "${wallpaper.id} vs "
              "#${color.toARGB32().toRadixString(16).padLeft(8, "0").substring(2)}"
              " = ${ratio.toStringAsFixed(2)}",
            );
          }
        }
      }

      expect(failures, isEmpty,
          reason: "these combinations are too faint to read:\n"
              "${failures.join("\n")}");
    });

    test("the old muted grey would not have passed on every wallpaper", () {
      // Documents what was replaced. The author name used AppTheme's muted
      // secondary tone; this records how much less contrast that carried than
      // the colours now used, so the change is measurable rather than a
      // matter of opinion.
      const oldColor = Color(0xFF7B6553);

      final oldWorst = ChatWallpaper.presets
          .map((w) => ChatWallpaper.contrastRatio(oldColor, w.lightestStop))
          .reduce((a, b) => a < b ? a : b);
      final newWorst = ChatWallpaper.presets
          .expand((w) => ChatWallpaper.authorColors
              .map((c) => ChatWallpaper.contrastRatio(c, w.lightestStop)))
          .reduce((a, b) => a < b ? a : b);

      expect(newWorst, greaterThan(oldWorst),
          reason: "the replacement should be more legible, not merely "
              "different");
      expect(oldWorst, lessThan(aa),
          reason: "if the old colour already passed, the stated reason for "
              "changing it was wrong");
    });

    test("every preset is dark enough for light text", () {
      // The wallpapers carry the same near-black the rest of the app sits on.
      // A preset that drifted light would swallow the light bubble text, which
      // no per-colour check would catch.
      for (final wallpaper in ChatWallpaper.presets) {
        expect(
          wallpaper.lightestStop.computeLuminance(),
          lessThan(0.25),
          reason: "${wallpaper.id} is light enough to swallow the light "
              "bubble text",
        );
      }
    });
  });

  group("Author colours", () {
    test("are stable for a given person", () {
      // A colour that changes between builds is noise, not identity.
      expect(
        ChatWallpaper.authorColor("amina"),
        ChatWallpaper.authorColor("amina"),
      );
    });

    test("distinguish people in a group", () {
      // Not a guarantee of uniqueness — the palette is finite — but a handful
      // of names should not all collapse onto one colour.
      final names = ["amina", "brice", "chantal", "divine", "emeka", "fabrice"];
      final colors = names.map(ChatWallpaper.authorColor).toSet();

      expect(colors.length, greaterThan(1),
          reason: "if everyone shares a colour the labels carry no "
              "information beyond the text itself");
    });

    test("an empty username does not throw", () {
      expect(ChatWallpaper.authorColor(""), isNotNull);
    });
  });

  group("Wallpaper selection", () {
    test("an unknown id falls back to the default", () {
      // Storage outlives code. A preset that is renamed or removed must not
      // make a conversation unopenable.
      expect(ChatWallpaper.byId("no-such-wallpaper").id,
          ChatWallpaper.charcoal.id);
      expect(ChatWallpaper.byId(null).id, ChatWallpaper.charcoal.id);
    });

    test("ids are unique", () {
      final ids = ChatWallpaper.presets.map((w) => w.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: "a duplicate id makes byId ambiguous and the picker's tick "
              "land on the wrong row");
    });

    test("there is more than one to choose from", () {
      expect(ChatWallpaper.presets.length, greaterThan(1));
    });
  });

  group("The online dot", () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets("shows when someone is reachable", (tester) async {
      await tester.pumpWidget(wrap(const OnlineDot(online: true)));

      expect(find.byType(OnlineDot), findsOneWidget);
      expect(tester.getSize(find.byType(Container)).width, greaterThan(0));
    });

    testWidgets("takes no space when nobody is", (tester) async {
      // An always-present grey dot would be worse than none: it reads as a
      // status when it is only a placeholder.
      await tester.pumpWidget(wrap(const OnlineDot(online: false)));

      expect(find.byType(Container), findsNothing);
      expect(tester.getSize(find.byType(OnlineDot)), Size.zero);
    });

    testWidgets("badges its child without replacing it", (tester) async {
      await tester.pumpWidget(wrap(
        const OnlineBadge(
          online: true,
          child: CircleAvatar(radius: 24, child: Text("A")),
        ),
      ));

      expect(find.text("A"), findsOneWidget);
      expect(find.byType(OnlineDot), findsOneWidget);
    });

    testWidgets("leaves the child alone when offline", (tester) async {
      await tester.pumpWidget(wrap(
        const OnlineBadge(
          online: false,
          child: CircleAvatar(radius: 24, child: Text("A")),
        ),
      ));

      expect(find.text("A"), findsOneWidget);
      expect(find.byType(OnlineDot), findsNothing);
    });

    testWidgets("is announced to screen readers", (tester) async {
      // A colour-only status is invisible to anyone using a screen reader,
      // and colour-blind users get nothing from green against nothing.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const OnlineDot(online: true)));

      expect(find.bySemanticsLabel("Online"), findsOneWidget);
      handle.dispose();
    });
  });
}
