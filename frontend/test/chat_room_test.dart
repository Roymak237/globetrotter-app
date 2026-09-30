import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/chat_room_screen.dart";
import "package:globetrotter/services/chat_service.dart";
import "package:globetrotter/utils/theme.dart";
import "package:provider/provider.dart";

/// Stands in for the network. Records the cursor of every fetch so a test can
/// assert on what was actually asked for, not just on what ended up on screen.
class _FakeChatService extends ChatService {
  final List<String?> cursors = [];
  List<ChatMessage> Function(String? since) responder;

  _FakeChatService({List<ChatMessage>? tail})
      : responder = ((since) => since == null ? (tail ?? const []) : const []);

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? since,
  }) async {
    cursors.add(since);
    return responder(since);
  }

  @override
  Future<void> markRead({
    required String token,
    required String roomId,
  }) async {}
}

class _SignedInAuth extends AuthProvider {
  @override
  String? get token => "test-token";

  @override
  User? get currentUser =>
      User(id: "u1", username: "me", preferences: const []);
}

const ChatRoom _room = ChatRoom(
  id: "r1",
  type: ChatRoomType.direct,
  name: "Amina",
  members: ["me", "friend"],
  otherUsername: "friend",
);

ChatMessage _message(String id, String createdAt, String text) => ChatMessage(
      id: id,
      roomId: "r1",
      username: "friend",
      createdAt: createdAt,
      text: text,
    );

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedInAuth()),
      ],
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    );

/// Mount the room and let the opening fetch resolve.
Future<_FakeChatService> _open(WidgetTester tester,
    {List<ChatMessage>? tail}) async {
  final service = _FakeChatService(tail: tail);
  await tester.pumpWidget(
    _host(ChatRoomScreen(room: _room, service: service)),
  );
  await tester.pump();
  await tester.pump();
  return service;
}

/// Tear the screen down so the poll timer is cancelled before the test ends.
Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group("Chat room stays current", () {
    // The bug this covers: _pollNew() used to return early whenever the thread
    // was empty, because it built its cursor from the last message it held.
    // With nothing to build a cursor from, every later tick stopped at the
    // same guard, so a conversation opened before the first reply arrived
    // never updated again. Reopening the screen was the only way to see
    // anything, which is why it looked like you had to sign out and back in.
    testWidgets("an empty room picks up the first message that arrives",
        (tester) async {
      final service = await _open(tester);
      expect(find.text("Bonjour"), findsNothing);

      // The first message lands while the screen is open and still empty.
      service.responder = (since) =>
          since == null ? [_message("m1", "2024-01-01T10:00:00", "Bonjour")] : [];

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.text("Bonjour"), findsOneWidget);
      await _close(tester);
    });

    testWidgets("polls for the tail while empty, then switches to a cursor",
        (tester) async {
      final service = await _open(tester);

      // Opening the room asks for the tail.
      expect(service.cursors, [null]);

      // Still empty, so the poll must keep asking for the tail rather than
      // giving up for want of a cursor.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(service.cursors, [null, null]);

      service.responder = (since) =>
          since == null ? [_message("m1", "2024-01-01T10:00:00", "Bonjour")] : [];
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // Now that there is a message to anchor to, later polls go incremental.
      service.responder = (since) => const [];
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(service.cursors.last, "2024-01-01T10:00:00");

      await _close(tester);
    });

    testWidgets("does not duplicate a message it already holds",
        (tester) async {
      final first = _message("m1", "2024-01-01T10:00:00", "Bonjour");
      final service = await _open(tester, tail: [first]);
      expect(find.text("Bonjour"), findsOneWidget);

      // A cursorless refresh can legitimately return what we already have, so
      // the merge has to dedupe on id rather than trust the cursor filter.
      service.responder = (since) => [first];
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.text("Bonjour"), findsOneWidget);
      await _close(tester);
    });

    testWidgets("pull to refresh reloads an empty room", (tester) async {
      final service = await _open(tester);
      expect(find.text("Bonjour"), findsNothing);

      service.responder = (since) =>
          [_message("m1", "2024-01-01T10:00:00", "Bonjour")];

      // The empty state has to be draggable, otherwise refresh is unavailable
      // in exactly the state where someone most wants it.
      await tester.fling(
        find.text("No messages yet"),
        const Offset(0, 320),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text("Bonjour"), findsOneWidget);
      await _close(tester);
    });
  });

  group("Chat room call buttons", () {
    // The app bar gradient runs primaryDark on the left to secondary on the
    // right, and AppBar.actions render at the right-hand end. White icons on
    // that amber measure about 2.67:1, under the 3:1 WCAG asks for on
    // interface icons, which is why these two were reported as hard to see
    // while the title at the dark end read fine. Each action has to bring its
    // own dark backing rather than depend on where the gradient lands.
    for (final entry in {
      "voice": Icons.call_rounded,
      "video": Icons.videocam_rounded,
    }.entries) {
      testWidgets("the ${entry.key} button sits on its own dark disc",
          (tester) async {
        await _open(tester);

        final button = find.widgetWithIcon(IconButton, entry.value);
        expect(button, findsOneWidget);

        final backing = find.ancestor(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.color == AppTheme.primaryDark &&
                widget.shape is CircleBorder,
          ),
        );
        expect(backing, findsOneWidget);

        await _close(tester);
      });
    }

    testWidgets("call tooltips are translated", (tester) async {
      final service = _FakeChatService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _SignedInAuth()),
          ],
          child: MaterialApp(
            locale: const Locale("fr"),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ChatRoomScreen(room: _room, service: service),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byTooltip("Appel vocal"),
        findsOneWidget,
        reason: "the tooltips were hardcoded English",
      );
      expect(find.byTooltip("Appel vidéo"), findsOneWidget);

      await _close(tester);
    });
  });
}
