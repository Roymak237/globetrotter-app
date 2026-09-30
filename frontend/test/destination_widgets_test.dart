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
    final free = language == "fr" ? "Gratuit" : "Free";

    testWidgets("$language card distinguishes unknown from known zero cost",
        (tester) async {
      await tester.pumpWidget(testApp(place(), language));
      await tester.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text(free), findsNothing);
      expect(tester.takeException(), isNull);

      // A place that costs nothing says so. The two states must never
      // collapse into the same string, because one means "we know it is
      // free" and the other means "we do not know".
      await tester.pumpWidget(testApp(place(cost: 0), language));
      await tester.pumpAndSettle();
      expect(find.text(free), findsOneWidget);
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
              ? "Nous n'avons pas encore pu situer ce lieu sur la carte."
              : "We have not been able to place this one on the map yet."),
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

    testWidgets("$language detail says whether a pin is the place or the area",
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final approximate = language == "fr"
          ? "Emplacement approximatif : le quartier, pas l'entrée"
          : "Approximate: the neighbourhood, not the door";

      // Most of these venues are known only by their quarter. Dropping a pin
      // there is useful, but only if the screen admits the pin is the
      // neighbourhood and not the front door.
      await tester.pumpWidget(testApp(
          place(cost: 6000, extra: {
            "latitude": 3.894018,
            "longitude": 11.510882,
            "location_precision": "area",
          }),
          language,
          detail: true));
      await tester.pumpAndSettle();
      expect(find.text(approximate), findsOneWidget);

      // A venue-level pin must not carry the warning, or the warning stops
      // meaning anything.
      await tester.pumpWidget(testApp(
          place(cost: 6000, extra: {
            "latitude": 3.892521,
            "longitude": 11.510106,
            "location_precision": "exact",
          }),
          language,
          detail: true));
      await tester.pumpAndSettle();
      expect(find.text(approximate), findsNothing);
    });

    testWidgets("$language detail shows where a price came from",
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const basis = "Indicative cost of a sit-down meal for one.";

      await tester.pumpWidget(testApp(
          place(cost: 6000, extra: {"cost_notes": basis}), language,
          detail: true));
      await tester.pumpAndSettle();
      // The tile is labelled as an estimate; this line says what kind.
      expect(find.text(basis), findsOneWidget);
      expect(find.text(language == "fr" ? "6k XAF / jour" : "6k XAF / day"),
          findsOneWidget);
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
