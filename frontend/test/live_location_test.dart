import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/shared_location.dart";
import "package:globetrotter/utils/theme.dart";
import "package:globetrotter/widgets/map_action_button.dart";

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group("SharedLocation parsing", () {
    test("reads a well formed payload", () {
      final location = SharedLocation.tryFromJson({
        "username": "ayuk",
        "display_name": "Ayuk N.",
        "avatar_url": "/media/a.jpg",
        "latitude": 3.848,
        "longitude": 11.5021,
        "accuracy": 12.5,
        "updated_at": "2024-05-01T10:00:00+00:00",
      });

      expect(location, isNotNull);
      expect(location!.displayName, "Ayuk N.");
      expect(location.point.latitude, closeTo(3.848, 0.0001));
      expect(location.accuracy, 12.5);
      expect(location.updatedAt?.isUtc, isTrue);
    });

    test("falls back to the username when no display name is set", () {
      final location = SharedLocation.tryFromJson({
        "username": "ayuk",
        "latitude": 3.848,
        "longitude": 11.5021,
      });

      expect(location?.displayName, "ayuk");
    });

    test("refuses a payload with no coordinates", () {
      // A half-parsed payload would otherwise become a marker at 0,0, which
      // looks like a real answer and is not one.
      expect(
        SharedLocation.tryFromJson({"username": "ayuk"}),
        isNull,
      );
    });

    test("refuses coordinates that are off the globe", () {
      expect(
        SharedLocation.tryFromJson({
          "username": "ayuk",
          "latitude": 120.0,
          "longitude": 11.5,
        }),
        isNull,
      );
    });
  });

  group("MapActionButton", () {
    testWidgets("shows the idle crosshair when not following", (tester) async {
      await tester.pumpWidget(
        wrap(
          MapActionButton(
            locating: false,
            hasCurrentLocation: true,
            following: false,
            onPressed: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(find.byIcon(Icons.navigation_rounded), findsNothing);
    });

    testWidgets("switches icon once the camera is following", (tester) async {
      await tester.pumpWidget(
        wrap(
          MapActionButton(
            locating: false,
            hasCurrentLocation: true,
            following: true,
            semanticLabel: "Stop following my position",
            onPressed: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);

      final semantics = tester.getSemantics(find.byType(MapActionButton).first);
      expect(semantics.label, "Stop following my position");

      // The button also has to look switched on, otherwise a map that keeps
      // sliding back to the traveller reads as a bug rather than a mode.
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(MapActionButton),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppTheme.primary);
    });

    testWidgets("stays idle-looking without a fix, even when following is set",
        (tester) async {
      // Following with nothing to follow would be a lie: the button would look
      // active while the map never moves.
      await tester.pumpWidget(
        wrap(
          MapActionButton(
            locating: false,
            hasCurrentLocation: false,
            following: true,
            onPressed: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    });
  });

  group("Tracker wording", () {
    test("every locale carries its own tracker strings", () {
      const en = AppLocalizations(Locale("en"));
      const fr = AppLocalizations(Locale("fr"));
      const cpe = AppLocalizations(Locale("cpe"));

      expect(en.trackerSharingOff, "Not sharing");
      expect(fr.trackerSharingTitle, "Partager ma position en direct");
      expect(cpe.trackerSharingOn, "You dey share with your groups");

      // The explainer is the only place the retention rule is stated, so it
      // must not quietly fall back to English.
      expect(fr.trackerSharingExplainer, contains("30 minutes"));
      expect(fr.trackerSharingExplainer, isNot(en.trackerSharingExplainer));
    });
  });
}
