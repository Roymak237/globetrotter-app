import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/providers/theme_provider.dart";
import "package:globetrotter/screens/about_developer_screen.dart";
import "package:globetrotter/screens/chat_room_screen.dart";
import "package:globetrotter/screens/profile_screen.dart";
import "package:globetrotter/services/chat_service.dart";
import "package:globetrotter/utils/chat_wallpaper.dart";
import "package:globetrotter/utils/chat_wallpaper_store.dart";
import "package:globetrotter/utils/theme.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

class _Auth extends AuthProvider {
  @override
  String get token => "theme-fixture";

  @override
  User get currentUser => User(id: "me", username: "traveler", preferences: []);

  @override
  Future<User> fetchProfile() async => currentUser;
}

class _Chat extends ChatService {
  @override
  Future<void> markRead(
      {required String token, required String roomId}) async {}

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? since,
  }) async =>
      [
        for (final mine in [false, true])
          ChatMessage(
            id: "$mine",
            roomId: roomId,
            username: mine ? "me" : "amina",
            createdAt: "2026-01-01T12:00:00",
            mine: mine,
            text: mine ? "Outgoing message" : "Incoming message",
            replyTo: ReplyPreview(
                id: "quote-$mine",
                username: "friend",
                text: mine ? "Outgoing quote" : "Incoming quote"),
          ),
      ];
}

Widget _host(ThemeProvider theme, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ],
      child: Consumer<ThemeProvider>(
          builder: (_, provider, __) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: provider.mode,
                locale: const Locale("en"),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: child,
              )),
    );

/// Measure rendered text, including intermediate translucent decoration fills.
/// Sample every gradient segment, not just its most flattering endpoint.
void _expectReadableText(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final textElement in finder.evaluate()) {
    final rich = tester.widget<RichText>(find.descendant(
        of: find.byWidget(textElement.widget),
        matching: find.byType(RichText)));
    final ink = rich.text.style!.color!;
    final layers = <Color>[];
    List<Color>? gradient;
    textElement.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        if (decoration.gradient != null) {
          gradient = decoration.gradient!.colors;
          return false;
        }
        if (decoration.color != null) layers.add(decoration.color!);
      } else if (widget is ColoredBox) {
        layers.add(widget.color);
      }
      return true;
    });
    final stops = gradient ?? [Theme.of(textElement).scaffoldBackgroundColor];
    final samples = <Color>[stops.first];
    for (var i = 1; i < stops.length; i++) {
      for (var step = 1; step <= 20; step++) {
        samples.add(Color.lerp(stops[i - 1], stops[i], step / 20)!);
      }
    }
    for (var background in samples) {
      for (final layer in layers.reversed) {
        background = Color.alphaBlend(layer, background);
      }
      expect(
          ChatWallpaper.contrastRatio(
              Color.alphaBlend(ink, background), background),
          greaterThanOrEqualTo(4.5),
          reason: rich.text.toPlainText());
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    for (final screen in [
      const AboutDeveloperScreen(),
      const ProfileScreen()
    ]) {
      testWidgets("${mode.name} ${screen.runtimeType} gradient text clears AA",
          (tester) async {
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        await theme.setMode(mode);
        await tester.pumpWidget(_host(theme, screen));
        await tester.pumpAndSettle();
        final hero = find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient ==
                AppTheme.brandGradient);
        expect(hero, findsOneWidget);
        _expectReadableText(
            tester, find.descendant(of: hero, matching: find.byType(Text)));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      "chat keeps wallpaper, draft, bubble and quote contrast across toggles",
      (tester) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await ChatWallpaperStore.save("theme-room", "palm");
    await tester.pumpWidget(_host(
        theme,
        ChatRoomScreen(
          room: const ChatRoom(
              id: "theme-room",
              type: ChatRoomType.community,
              name: "Theme room"),
          service: _Chat(),
        )));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), "Unsent draft");
    final state = tester.state(find.byType(ChatRoomScreen));
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await theme.setMode(mode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final brightness =
          mode == ThemeMode.light ? Brightness.light : Brightness.dark;
      final palette = AppPalette(brightness);
      expect(tester.state(find.byType(ChatRoomScreen)), same(state));
      expect(find.text("Unsent draft"), findsOneWidget);
      final wallpaper = find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration ==
              ChatWallpaper.byId("palm").decorationFor(brightness));
      expect(wallpaper, findsOneWidget);
      for (final label in [
        "Incoming message",
        "Outgoing message",
        "Incoming quote",
        "Outgoing quote",
        "amina"
      ]) {
        _expectReadableText(tester, find.text(label));
      }
      expect(tester.widget<Text>(find.text("Outgoing message")).style!.color,
          palette.onPrimary);
      expect(tester.widget<Text>(find.text("Incoming message")).style!.color,
          palette.textPrimary);
      expect(
          Theme.of(tester.element(find.byType(TextField)))
              .inputDecorationTheme
              .fillColor,
          palette.surface);
      await tester.tap(find.byTooltip("Wallpaper"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final preset in ChatWallpaper.presets) {
        expect(
            find.byWidgetPredicate((widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).gradient ==
                    preset.decorationFor(brightness).gradient),
            findsOneWidget);
      }
      Navigator.of(tester.element(find.byType(ChatRoomScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await ChatWallpaperStore.load("theme-room"), "palm");
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
