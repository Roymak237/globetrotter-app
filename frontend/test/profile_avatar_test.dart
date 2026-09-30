import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/utils/constants.dart";
import "package:globetrotter/utils/media_url.dart";
import "package:globetrotter/widgets/account_dialogs.dart";
import "package:globetrotter/widgets/user_avatar.dart";

/// The backend stores avatars as `/api/media/<32 hex>.<ext>` and accepts
/// nothing else: PUT /api/me/avatar answers 400 "avatar must be an uploaded
/// image" for anything that does not match, which was verified against a
/// running server (see scripts/probe_avatar_api.ps1).
const _storedAvatar = "/api/media/8feeb40289f344ce9ebc4da6d3ca2610.png";

User _user({String avatarUrl = ""}) => User(
      id: "u1",
      username: "amina",
      displayName: "Amina",
      avatarUrl: avatarUrl,
      preferences: const [],
    );

Future<void> _openEditor(
  WidgetTester tester, {
  required User user,
  Future<String?> Function()? onPickAvatar,
  required void Function(String avatarUrl) onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAccountDetailsEditor(
              context,
              user: user,
              onPickAvatar: onPickAvatar,
              onSave: (_, __, ___, avatarUrl) async => onSaved(avatarUrl),
            ),
            child: const Text("open"),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

void main() {
  group("resolveMediaUrl", () {
    test("makes a stored avatar path absolute", () {
      // Image.network hands the string to HttpClient.getUrl on mobile and
      // desktop, which rejects anything without a scheme. A browser resolves
      // it against the page origin, so leaving it relative works on web and
      // fails on a phone - the kind of gap that survives testing in Chrome.
      final resolved = resolveMediaUrl(_storedAvatar);

      expect(Uri.parse(resolved).isAbsolute, isTrue);
      expect(resolved, "${AppConstants.backendBaseUrl}$_storedAvatar");
    });

    test("leaves an already absolute http(s) URL alone", () {
      const remote = "https://cdn.example.com/a.png";
      expect(resolveMediaUrl(remote), remote);
    });

    test("returns empty for nothing to show", () {
      expect(resolveMediaUrl(""), "");
      expect(resolveMediaUrl("   "), "");
    });

    test("refuses schemes that are not fetchable images", () {
      // An avatar renders for everyone who sees the profile, so it is a
      // tempting place to park a payload.
      expect(resolveMediaUrl("data:image/png;base64,iVBORw0KGgo="), "");
      expect(resolveMediaUrl("javascript:alert(1)"), "");
    });

    test("does not adopt a foreign host from a protocol-relative URL", () {
      // Uri.resolve would keep evil.example.com and merely lend it our
      // scheme, which looks local at a glance but is not.
      expect(resolveMediaUrl("//evil.example.com/a.png"), "");
    });
  });

  group("UserAvatar", () {
    testWidgets("falls back to an initial when there is no photo",
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(avatarUrl: "", name: "Amina")),
      ));

      expect(find.text("A"), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets("requests an absolute URL when a photo is set", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: UserAvatar(avatarUrl: _storedAvatar, name: "Amina"),
        ),
      ));

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as NetworkImage;
      expect(Uri.parse(provider.url).isAbsolute, isTrue,
          reason: "a relative src throws on Android and iOS");
    });

    testWidgets("shows a placeholder rather than an empty disc for a blank name",
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(avatarUrl: "", name: "   ")),
      ));

      expect(find.text("?"), findsOneWidget);
    });
  });

  group("Profile photo editor", () {
    testWidgets("uploads a picked photo and saves the returned path",
        (tester) async {
      // The whole point of the change: what reaches onSave has to be the
      // uploaded path, because the server rejects everything else.
      String? saved;
      await _openEditor(
        tester,
        user: _user(),
        onPickAvatar: () async => _storedAvatar,
        onSaved: (avatarUrl) => saved = avatarUrl,
      );

      expect(find.text("Using your initials"), findsOneWidget);

      await tester.tap(find.text("Upload photo"));
      await tester.pumpAndSettle();

      expect(find.text("Photo set"), findsOneWidget);

      await tester.tap(find.text("Save profile"));
      await tester.pumpAndSettle();

      expect(saved, _storedAvatar);
    });

    testWidgets("offers no way to type a URL", (tester) async {
      // The old field asked for a public https:// address and validated for
      // one, while the server accepted only its own uploaded paths. Every
      // value a user could enter was rejected with 400. Re-introducing a free
      // text URL box would restore a control that cannot succeed.
      await _openEditor(
        tester,
        user: _user(),
        onPickAvatar: () async => _storedAvatar,
        onSaved: (_) {},
      );

      expect(find.text("Avatar URL (optional)"), findsNothing);
      expect(find.text("https://…"), findsNothing);
      // The old control was the only URL-keyboard field in the dialog.
      expect(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.keyboardType == TextInputType.url),
        findsNothing,
      );
    });

    testWidgets("keeps the existing photo when the picker is cancelled",
        (tester) async {
      String? saved;
      await _openEditor(
        tester,
        user: _user(avatarUrl: _storedAvatar),
        onPickAvatar: () async => null, // cancelled
        onSaved: (avatarUrl) => saved = avatarUrl,
      );

      await tester.tap(find.text("Change photo"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Save profile"));
      await tester.pumpAndSettle();

      expect(saved, _storedAvatar,
          reason: "cancelling must not wipe the photo already set");
    });

    testWidgets("removing clears the photo", (tester) async {
      String? saved;
      await _openEditor(
        tester,
        user: _user(avatarUrl: _storedAvatar),
        onPickAvatar: () async => _storedAvatar,
        onSaved: (avatarUrl) => saved = avatarUrl,
      );

      expect(find.text("Photo set"), findsOneWidget);

      await tester.tap(find.text("Remove"));
      await tester.pumpAndSettle();
      expect(find.text("Using your initials"), findsOneWidget);

      await tester.tap(find.text("Save profile"));
      await tester.pumpAndSettle();

      expect(saved, "");
    });

    testWidgets("surfaces an upload failure instead of failing silently",
        (tester) async {
      await _openEditor(
        tester,
        user: _user(),
        onPickAvatar: () async => throw Exception("File must be 10 MB or smaller."),
        onSaved: (_) {},
      );

      await tester.tap(find.text("Upload photo"));
      await tester.pumpAndSettle();

      expect(find.text("File must be 10 MB or smaller."), findsOneWidget);
      // The dialog has to stay usable after a failed upload.
      expect(find.text("Save profile"), findsOneWidget);
    });
  });
}
