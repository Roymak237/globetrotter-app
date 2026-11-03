import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/providers/favorites_provider.dart";
import "package:globetrotter/providers/locale_provider.dart";
import "package:globetrotter/providers/theme_provider.dart";
import "package:globetrotter/screens/login_screen.dart";
import "package:globetrotter/screens/home_screen.dart";
import "package:globetrotter/screens/register_screen.dart";
import "package:globetrotter/screens/forgot_password_screen.dart";
import "package:globetrotter/utils/chat_wallpaper.dart";
import "package:globetrotter/utils/theme.dart";
import "package:globetrotter/widgets/auth_widgets.dart";
import "package:globetrotter/widgets/bottom_nav.dart";
import "package:globetrotter/widgets/destination_card.dart";
import "package:globetrotter/widgets/theme_toggle.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

Widget host(ThemeProvider provider, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: theme.mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets("${mode.name} selected filter chips have readable labels",
        (tester) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await provider.setMode(mode);
      await tester.pumpWidget(host(
          provider,
          Scaffold(
              body: FilterChip(
            label: const Text("Selected stop"),
            selected: true,
            onSelected: (_) {},
          ))));
      await tester.pumpAndSettle();
      final text = tester.widget<RichText>(find.descendant(
          of: find.text("Selected stop"), matching: find.byType(RichText)));
      final palette = AppTheme.of(tester.element(find.byType(FilterChip)));
      expect(text.text.style!.color, palette.onPrimary);
      expect(
          ChatWallpaper.contrastRatio(text.text.style!.color!, palette.primary),
          greaterThanOrEqualTo(4.5));
    });
  }

  for (final screen in [const RegisterScreen(), const ForgotPasswordScreen()]) {
    testWidgets("${screen.runtimeType} shares the auth theme control",
        (tester) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(host(provider, screen));
      await tester.pump();
      await tester.tap(find.byTooltip("Switch to light theme"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(Theme.of(tester.element(find.byType(ThemeToggle))).brightness,
          Brightness.light);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets("home toggle preserves the selected tab at phone width",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(host(provider, const HomeScreen()));
    await tester.pump();
    // Change the real navigation state without activating location tracking.
    tester.widget<BottomNav>(find.byType(BottomNav)).onTap(2);
    await tester.pump();
    final state = tester.state(find.byType(HomeScreen));
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.tap(find.byType(ThemeToggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.mode, mode);
      expect(tester.state(find.byType(HomeScreen)), same(state));
      expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 2);
      final context = tester.element(find.byType(HomeScreen));
      expect(Theme.of(context).scaffoldBackgroundColor,
          mode == ThemeMode.light ? Colors.white : const Color(0xFF0A0A0A));
      expect(tester.widget<AppBar>(find.byType(AppBar).first).backgroundColor,
          AppTheme.of(context).background);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("toggle is labelled, keyboard accessible, and updates both ways",
      (tester) async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester
          .pumpWidget(host(provider, const Scaffold(body: ThemeToggle())));
      await tester.pumpAndSettle();
      expect(find.byTooltip("Switch to light theme"), findsOneWidget);
      expect(find.bySemanticsLabel("Switch to light theme"), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(provider.mode, ThemeMode.light);
      expect(find.byTooltip("Switch to dark theme"), findsOneWidget);
      expect(
          Theme.of(tester.element(find.byType(ThemeToggle)))
              .scaffoldBackgroundColor,
          Colors.white);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(provider.mode, ThemeMode.dark);
    } finally {
      // Flutter verifies handles before addTearDown callbacks run.
      semantics.dispose();
    }
  });

  testWidgets("login form switches to white without clearing typed credentials",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(host(provider, const LoginScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, "traveler");
    await tester.tap(find.byTooltip("Switch to light theme"));
    // Auth photography has a periodic slideshow: use bounded pumps, not settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final context = tester.element(find.byType(AuthFormCard));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(Theme.of(context).inputDecorationTheme.fillColor, Colors.white);
    final panels = tester.widgetList<Container>(find.descendant(
      of: find.byType(AuthFormCard),
      matching: find.byType(Container),
    ));
    expect(
        panels.any((panel) =>
            panel.decoration is BoxDecoration &&
            (panel.decoration! as BoxDecoration).color == Colors.white),
        isTrue);
    expect(find.text("traveler"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
        "${mode.name} cards and bottom navigation use semantic surfaces",
        (tester) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await provider.setMode(mode);
      final destination = Destination.fromJson({
        "id": "theme-fixture",
        "name": "Theme fixture",
        "region": "Centre",
        "description": "No photograph",
        "tags": <String>[],
      });
      await tester.pumpWidget(host(
          provider,
          Scaffold(
            body: SingleChildScrollView(
                child: DestinationCard(destination: destination)),
            bottomNavigationBar: BottomNav(currentIndex: 0, onTap: (_) {}),
          )));
      await tester.pumpAndSettle();
      final palette = AppTheme.of(tester.element(find.byType(DestinationCard)));
      for (final type in [DestinationCard, BottomNav]) {
        final containers = tester.widgetList<Container>(find.descendant(
          of: find.byType(type),
          matching: find.byType(Container),
        ));
        expect(
            containers.any((container) =>
                container.decoration is BoxDecoration &&
                (container.decoration! as BoxDecoration).color ==
                    palette.surface),
            isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a pushed route and open dialog update without navigation reset",
      (tester) async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(host(
        provider,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (context) => Scaffold(
                                      body: TextButton(
                                          onPressed: () => showDialog<void>(
                                                context: context,
                                                builder: (_) =>
                                                    const AlertDialog(
                                                        title: Text(
                                                            "Theme dialog")),
                                              ),
                                          child: const Text("Open dialog")),
                                    )),
                          ),
                      child: const Text("Next")),
                ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Next"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Open dialog"));
    await tester.pumpAndSettle();
    await provider.toggle();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AlertDialog));
    expect(Theme.of(context).dialogTheme.backgroundColor, Colors.white);
    expect(find.text("Theme dialog"), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text("Open dialog"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
