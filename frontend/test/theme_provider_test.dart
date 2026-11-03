import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/providers/theme_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("fresh installs default to dark, irrespective of the system", () async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    expect(provider.mode, ThemeMode.dark);
    await provider.load();
    expect(provider.isDark, isTrue);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    test("${mode.name} survives a provider restart", () async {
      final first = ThemeProvider();
      final restored = ThemeProvider();
      addTearDown(first.dispose);
      addTearDown(restored.dispose);
      await first.setMode(ThemeMode.light);
      await first.setMode(mode);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(ThemeProvider.preferenceKey), mode.name);
      await restored.load();
      expect(restored.mode, mode);
    });
  }

  test("invalid preference safely falls back to dark", () async {
    SharedPreferences.setMockInitialValues(
        {ThemeProvider.preferenceKey: "bad"});
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await provider.load();
    expect(provider.mode, ThemeMode.dark);
  });

  test("rapid toggles notify immediately and persist in selection order",
      () async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);
    final writes = [provider.toggle(), provider.toggle(), provider.toggle()];
    expect(provider.mode, ThemeMode.light);
    expect(notifications, 3);
    await Future.wait(writes);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(ThemeProvider.preferenceKey), "light");
  });

  test("late hydration cannot overwrite a user selection", () async {
    final preferences = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final provider = ThemeProvider(loadPreferences: () => pending.future);
    addTearDown(provider.dispose);
    final loading = provider.load();
    final writing = provider.toggle();
    pending.complete(preferences);
    await Future.wait([loading, writing]);
    expect(provider.mode, ThemeMode.light);
    expect(preferences.getString(ThemeProvider.preferenceKey), "light");
  });

  test("storage failure does not prevent an in-memory theme change", () async {
    final provider = ThemeProvider(
      loadPreferences: () async => throw StateError("storage unavailable"),
    );
    addTearDown(provider.dispose);
    await provider.load();
    expect(provider.isDark, isTrue);
    await provider.toggle();
    expect(provider.mode, ThemeMode.light);
  });

  test("disposing during hydration does not notify a dead provider", () async {
    final pending = Completer<SharedPreferences>();
    final provider = ThemeProvider(loadPreferences: () => pending.future);
    var notifications = 0;
    provider.addListener(() => notifications++);
    final loading = provider.load();
    provider.dispose();
    pending.complete(await SharedPreferences.getInstance());
    await loading;
    expect(notifications, 0);
  });
}
