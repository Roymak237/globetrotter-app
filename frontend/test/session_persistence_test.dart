import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/services/auth_service.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Two promises are covered here, both of which the app used to break:
///
///  1. Creating an account signs you in. It used to bounce the new arrival
///     back to the sign-in screen to retype credentials typed seconds before.
///  2. Signing in once is enough. A token was written to storage on every
///     sign-in and then never read back, so the installed Android app opened
///     on the sign-in screen no matter how recently it had been used.

const _profile = {
  "id": "u-1",
  "username": "amina",
  "display_name": "Amina",
  "email": "amina@example.com",
  "home_region": "Centre",
  "avatar_url": "",
  "preferences": ["beaches"],
};

/// A stand-in server. [onRequest] records what was asked for so a test can
/// assert that, for example, nothing was asked for at all.
MockClient _server({
  int registerStatus = 201,
  Map<String, dynamic>? registerBody,
  int refreshStatus = 200,
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    final path = request.url.path;
    if (path.endsWith("/auth/register")) {
      return http.Response(
        json.encode(registerBody ??
            {
              "message": "user registered successfully",
              "username": "amina",
              "token": "fresh-token",
              "user": _profile,
            }),
        registerStatus,
      );
    }
    if (path.endsWith("/auth/login")) {
      return http.Response(
        json.encode({"token": "fresh-token", "user": _profile}),
        200,
      );
    }
    if (path.endsWith("/auth/refresh")) {
      if (refreshStatus != 200) {
        return http.Response(
          json.encode({"error": "authentication required"}),
          refreshStatus,
        );
      }
      return http.Response(
        json.encode({"token": "rotated-token", "user": _profile}),
        200,
      );
    }
    return http.Response(json.encode({"error": "unexpected ${request.url}"}), 404);
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("creating an account signs you in", () {
    test("register stores the session the server hands back", () async {
      final service = AuthService(client: _server());

      await service.register(username: "amina", password: "TestPass123!");

      expect(service.isAuthenticated, isTrue,
          reason: "a new arrival should already be signed in");
      expect(service.token, "fresh-token");
      expect(service.currentUser?.username, "amina");
    });

    test("the session survives a restart without signing in again", () async {
      await AuthService(client: _server())
          .register(username: "amina", password: "TestPass123!");

      // A second instance stands in for the next cold launch: same storage,
      // no memory of the first.
      final relaunched = AuthService(client: _server());
      await relaunched.loadToken();

      expect(relaunched.isAuthenticated, isTrue);
      expect(relaunched.currentUser?.displayName, "Amina",
          reason: "the restored session should know who it belongs to");
    });

    test("a server that withholds a session is still a success", () async {
      // Registration must not fail just because the token is absent; the
      // account exists and the caller can fall back to signing in.
      final service = AuthService(
        client: _server(registerBody: {
          "message": "user registered successfully",
          "username": "amina",
        }),
      );

      await expectLater(
        service.register(username: "amina", password: "TestPass123!"),
        completion(isTrue),
      );
      expect(service.isAuthenticated, isFalse);
    });
  });

  group("staying signed in", () {
    test("restoring reads the stored session, not the network", () async {
      await AuthService(client: _server())
          .login(username: "amina", password: "TestPass123!");

      var calls = 0;
      final relaunched =
          AuthService(client: _server(onRequest: (_) => calls++));
      await relaunched.loadToken();

      expect(relaunched.isAuthenticated, isTrue);
      expect(calls, 0,
          reason: "launch must not depend on having a signal");
    });

    test("a revoked session is cleared", () async {
      await AuthService(client: _server())
          .login(username: "amina", password: "TestPass123!");

      final relaunched = AuthService(client: _server(refreshStatus: 401));
      await relaunched.loadToken();
      final stillValid = await relaunched.refreshSession();

      expect(stillValid, isFalse);
      expect(relaunched.isAuthenticated, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString("auth_token"), isNull,
          reason: "a rejected session must not be restored again");
      expect(prefs.getString("auth_user"), isNull);
    });

    test("an unreachable server does not sign anyone out", () async {
      await AuthService(client: _server())
          .login(username: "amina", password: "TestPass123!");

      final offline = AuthService(
        client: MockClient((_) async => throw const SocketishFailure()),
      );
      await offline.loadToken();
      final stillValid = await offline.refreshSession();

      expect(stillValid, isTrue,
          reason: "no signal is not the same as being turned away");
      expect(offline.isAuthenticated, isTrue);
    });

    test("signing out clears the stored profile too", () async {
      final service = AuthService(client: _server());
      await service.login(username: "amina", password: "TestPass123!");

      await service.logout();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString("auth_token"), isNull);
      expect(prefs.getString("auth_user"), isNull,
          reason: "the next person on a shared phone must not see this name");
    });

    test("the cached profile round-trips", () {
      // loadToken rebuilds the user from what _cacheUser wrote, so the two
      // have to agree on field names. They are the server's names, not Dart's.
      final original = User.fromJson(Map<String, dynamic>.from(_profile));
      final restored = User.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.displayName, original.displayName);
      expect(restored.email, original.email);
      expect(restored.homeRegion, original.homeRegion);
      expect(restored.preferences, original.preferences);
    });
  });

  group("the provider exposes the same behaviour", () {
    testWidgets("register leaves the provider authenticated", (tester) async {
      final provider = AuthProvider(client: _server());
      addTearDown(provider.dispose);

      await provider.register(username: "amina", password: "TestPass123!");

      expect(provider.isAuthenticated, isTrue);
      expect(provider.currentUser?.username, "amina");
    });
  });
}

/// A failure that is not an HTTP rejection. Named rather than reusing
/// SocketException so the test does not depend on dart:io.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => "Connection failed";
}
