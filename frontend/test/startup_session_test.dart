import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/app.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/login_screen.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Which screen a cold launch opens.
///
/// The installed Android app showed the sign-in screen every time, however
/// recently it had been used: a token was written to storage on sign-in and
/// then never read back. These check the decision itself.
///
/// The signed-in destination is a stand-in rather than the real home screen.
/// Home runs animations and timers that never settle under the test binding,
/// so mounting it here would test the harness, not the gate. Whether home
/// renders is covered by its own tests; what matters here is which way the
/// gate went.

const _profile = {
  "id": "u-1",
  "username": "amina",
  "display_name": "Amina",
  "email": "",
  "home_region": "",
  "avatar_url": "",
  "preferences": <String>[],
};

MockClient _server({int refreshStatus = 200}) {
  return MockClient((request) async {
    if (refreshStatus != 200) {
      return http.Response(
          json.encode({"error": "authentication required"}), refreshStatus);
    }
    return http.Response(
        json.encode({"token": "rotated", "user": _profile}), 200);
  });
}

Widget _gateUnder(AuthProvider provider) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: provider,
    child: MaterialApp(
      home: StartupGate(
        signedIn: (_) => const Scaffold(body: Text("IN THE APP")),
        signedOut: (_) => const Scaffold(body: Text("SIGN IN")),
      ),
    ),
  );
}

Future<void> _pumpGate(WidgetTester tester, {int refreshStatus = 200}) async {
  final provider = AuthProvider(client: _server(refreshStatus: refreshStatus));
  addTearDown(provider.dispose);
  await tester.pumpWidget(_gateUnder(provider));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("a fresh install is asked to sign in", (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpGate(tester);

    expect(find.text("SIGN IN"), findsOneWidget);
  });

  testWidgets("a returning traveller goes straight into the app",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "auth_token": "stored-token",
      "auth_user": json.encode(_profile),
    });

    await _pumpGate(tester);

    expect(find.text("IN THE APP"), findsOneWidget,
        reason: "signing in once should be enough");
  });

  testWidgets("a revoked session is sent back to sign in", (tester) async {
    SharedPreferences.setMockInitialValues({
      "auth_token": "revoked-token",
      "auth_user": json.encode(_profile),
    });

    await _pumpGate(tester, refreshStatus: 401);

    expect(find.text("SIGN IN"), findsOneWidget,
        reason: "a session the server withdrew must not open the app");
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString("auth_token"), isNull);
  });

  testWidgets("an upgrade with a token but no cached profile still opens",
      (tester) async {
    // Installs from the previous build have a token and no stored profile.
    // The upgrade itself must not sign them out.
    SharedPreferences.setMockInitialValues({"auth_token": "stored-token"});

    await _pumpGate(tester);

    expect(find.text("IN THE APP"), findsOneWidget);
  });

  testWidgets("a corrupt cached profile does not block the launch",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "auth_token": "stored-token",
      "auth_user": "{not json",
    });

    await _pumpGate(tester);

    expect(find.text("IN THE APP"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("an unreachable server keeps the traveller signed in",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "auth_token": "stored-token",
      "auth_user": json.encode(_profile),
    });

    final provider = AuthProvider(
      client: MockClient((_) async => throw Exception("Connection failed")),
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(_gateUnder(provider));
    await tester.pumpAndSettle();

    expect(find.text("IN THE APP"), findsOneWidget,
        reason: "no signal is not the same as being turned away");
  });

  testWidgets("the shipped app really does start at the gate", (tester) async {
    // The tests above exercise the gate directly, so this one confirms the
    // app is actually wired to it rather than straight to a login route.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(GlobetrotterApp(authClient: _server()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(StartupGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
