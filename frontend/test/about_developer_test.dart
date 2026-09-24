import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/screens/about_developer_screen.dart";

/// The page is a lazy `ListView`, so anything past the first screenful is
/// never built on the default 800x600 test surface, and every assertion about
/// it would pass for the wrong reason. A tall viewport puts the whole page in
/// frame at once.
Future<void> pumpAbout(WidgetTester tester, String language) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      // The app's own delegate stack, not the framework's. The stock Material
      // delegate throws on Pidgin, so wiring it directly here would fail the
      // test for a reason the real app never hits.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const AboutDeveloperScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("credits stay correct in every supported language",
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final language = locale.languageCode;
      await pumpAbout(tester, language);

      // The name and the institution are facts about a real person. A missing
      // translation must never quietly blank them out, so they are asserted in
      // every locale rather than only the default one.
      expect(find.text("Fru Chi Ehud Neba"), findsOneWidget,
          reason: "name missing in $language");
      expect(find.textContaining("ICT University"), findsOneWidget,
          reason: "institution missing in $language");

      // The status badge is the one claim on the page that expires. If the
      // degree is ever finished, this assertion is the reminder that the copy
      // has to change with it.
      final t = AppLocalizations(locale);
      expect(find.text(t.aboutDeveloperOngoing), findsOneWidget,
          reason: "ongoing badge missing in $language");
    }
  });

  testWidgets("no section falls back to a raw translation key", (tester) async {
    // `_text` returns the key itself when a lookup fails in every catalogue.
    // That renders as readable-looking camelCase, so it survives a glance at
    // the screen; only an assertion catches it.
    for (final locale in AppLocalizations.supportedLocales) {
      await pumpAbout(tester, locale.languageCode);

      expect(
        find.textContaining(RegExp(r"aboutDeveloper[A-Z]")),
        findsNothing,
        reason: "untranslated key leaked in ${locale.languageCode}",
      );
    }
  });

  testWidgets("the portrait is wired to a declared asset", (tester) async {
    await pumpAbout(tester, "en");

    // The image resolves here rather than falling back to initials, and that
    // is the check worth having: if the pubspec declaration for the portrait
    // were dropped, the load would fail and the monogram would take its place.
    final portrait = tester.widget<Image>(
      find.descendant(
        of: find.byType(ClipOval),
        matching: find.byType(Image),
      ),
    );
    expect((portrait.image as AssetImage).assetName, "assets/developer.jpg");
    expect(find.text("FN"), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
