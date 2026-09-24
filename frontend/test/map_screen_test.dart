import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/map_screen.dart";
import "package:provider/provider.dart";

/// Hosts the map the way the real app does, with a route table so that pushing
/// "/map" exercises the same path the destinations shortcut takes.
Widget host({required Widget home, String language = "en"}) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
    child: MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
      routes: {
        "/map": (_) => const MapScreen(isActive: false),
      },
    ),
  );
}

void main() {
  group("Map screen page chrome", () {
    // The screen is used two ways. Pushed as its own route it has to supply a
    // Scaffold, because nothing else will; embedded as a home tab it must not,
    // because the home shell already has one.
    testWidgets("brings its own scaffold when pushed as a route",
        (tester) async {
      await tester.pumpWidget(
        host(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, "/map"),
                  child: const Text("open map"),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text("open map"));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);

      // Without a Scaffold of its own the pushed map had no app bar, which
      // meant no back button and no way off the page.
      final scaffold = find.descendant(
        of: find.byType(MapScreen),
        matching: find.byType(Scaffold),
      );
      expect(scaffold, findsOneWidget);
      expect(
        find.descendant(of: scaffold, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets("can go back from the pushed route", (tester) async {
      await tester.pumpWidget(
        host(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, "/map"),
                  child: const Text("open map"),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text("open map"));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsNothing);
      expect(find.text("open map"), findsOneWidget);
    });

    testWidgets("adds no scaffold when embedded in the home shell",
        (tester) async {
      await tester.pumpWidget(
        host(
          home: const Scaffold(
            body: MapScreen(isActive: false, showScaffold: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(MapScreen),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
    });
  });

  group("Mapped places count", () {
    test("is translated, and singular is not just plural minus an s", () {
      const en = AppLocalizations(Locale("en"));
      const fr = AppLocalizations(Locale("fr"));
      const cpe = AppLocalizations(Locale("cpe"));

      expect(en.mappedPlaces(13), "13 mapped places");
      expect(en.mappedPlaces(1), "1 mapped place");

      // This string used to be built in Dart with a hardcoded English "s",
      // so it stayed English in every locale.
      expect(fr.mappedPlaces(13), "13 lieux cartographiés");
      expect(fr.mappedPlaces(1), "1 lieu cartographié");
      expect(cpe.mappedPlaces(13), "13 places for map");
      expect(cpe.mappedPlaces(1), "1 place for map");
    });

    test("leaves no unreplaced placeholder in any locale", () {
      for (final locale in AppLocalizations.supportedLocales) {
        final strings = AppLocalizations(locale);
        expect(strings.mappedPlaces(7), isNot(contains("{count}")));
        expect(strings.mappedPlaces(7), contains("7"));
      }
    });
  });
}
