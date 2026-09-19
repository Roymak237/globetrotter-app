import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/screens/destination_detail_screen.dart";
import "package:globetrotter/widgets/destination_card.dart";
import "package:globetrotter/widgets/destination_map.dart";
import "package:provider/provider.dart";

Destination place({num? cost, Map<String, dynamic> extra = const {}}) =>
    Destination.fromJson({
      "id": "test-place",
      "name": "Yaoundé place",
      "region": "Centre",
      "description": "A place in Yaoundé.",
      "avg_cost_per_day": cost,
      "latitude": null,
      "longitude": null,
      ...extra,
    });

Widget testApp(Destination destination, String language,
    {bool detail = false}) {
  // The detail screen hosts the comments thread, which reads the signed-in
  // user, so both providers have to be in scope for it to build.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(
      key: ObjectKey(destination),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: destination),
        builder: (_) => detail
            ? const DestinationDetailScreen()
            : Scaffold(
                body: SingleChildScrollView(
                  child: DestinationCard(destination: destination),
                ),
              ),
      ),
    ),
  );
}

void main() {
  for (final language in ["en", "fr"]) {
    final unavailable = language == "fr" ? "Non disponible" : "Not available";

    testWidgets("$language card distinguishes unknown from known zero cost",
        (tester) async {
      await tester.pumpWidget(testApp(place(), language));
      await tester.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text("0k XAF"), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(testApp(place(cost: 0), language));
      await tester.pumpAndSettle();
      expect(find.text("0k XAF"), findsOneWidget);
      expect(find.text(unavailable), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "$language detail shows metadata and pending location, not a map",
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final destination = place(extra: {
        "address": "Bastos, Yaoundé",
        "location_notes": "Entrance awaiting verification.",
        "location_sources": ["https://example.org/location"],
      });
      await tester.pumpWidget(testApp(destination, language, detail: true));
      await tester.pumpAndSettle();
      expect(find.byType(DestinationMap), findsNothing);
      expect(find.text(unavailable), findsOneWidget);
      expect(
          find.text(language == "fr"
              ? "Localisation en attente de vérification. Aucune position affichée sur la carte."
              : "Location pending verification. No map pin is shown."),
          findsOneWidget);
      expect(find.text("Bastos, Yaoundé"), findsOneWidget);
      expect(find.text("Entrance awaiting verification."), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is SelectableText &&
              widget.data == "https://example.org/location"),
          findsOneWidget);
      expect(
          find.text(language == "fr" ? "Adresse" : "Address"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      "gallery excludes the hero and duplicate assets with error fallback",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final destination = place(extra: {
      "image_asset": "tourist/city council.webp",
      "additional_image_assets": [
        "tourist/city council.webp",
        "missing-test-photo.jpg",
        "missing-test-photo.jpg",
        "",
      ],
    });
    await tester.pumpWidget(testApp(destination, "en", detail: true));
    await tester.pumpAndSettle();
    expect(find.text("More photos"), findsOneWidget);
    expect(find.text("Photo not available"), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                "assets/images/tourist/city council.webp"),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
