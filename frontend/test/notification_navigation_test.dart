import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/chat_room_screen.dart";
import "package:globetrotter/screens/notifications_screen.dart";
import "package:globetrotter/services/chat_service.dart";
import "package:globetrotter/services/social_service.dart";
import "package:provider/provider.dart";

/// The inbox used to be a list of statements with nothing behind them. Being
/// told that someone had written to you and then having to go and find the
/// conversation yourself is the complaint these tests exist to keep fixed.

class _FakeSocial extends SocialService {
  final List<AppNotification> items;

  /// Every id this screen asked the server to mark read.
  final List<String> markedRead = [];

  _FakeSocial(this.items);

  @override
  Future<({int unread, List<AppNotification> items})> fetchNotifications(
          String token) async =>
      (unread: items.where((n) => !n.read).length, items: items);

  @override
  Future<void> markNotificationsRead({
    required String token,
    List<String>? ids,
  }) async {
    markedRead.addAll(ids ?? const ["*"]);
  }
}

class _FakeChat extends ChatService {
  final List<ChatRoom> rooms;
  int fetchCount = 0;

  _FakeChat(this.rooms);

  @override
  Future<List<ChatRoom>> fetchRooms(String token) async {
    fetchCount += 1;
    return rooms;
  }

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? since,
  }) async =>
      const [];

  @override
  Future<void> markRead({
    required String token,
    required String roomId,
  }) async {}

  @override
  Future<Set<String>> presence(String token, String roomId) async => const {};
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

AppNotification _notification({
  required String id,
  String type = "message",
  String? roomId,
  String? destinationId,
  bool read = false,
}) =>
    AppNotification(
      id: id,
      type: type,
      text: "Amina sent you a message",
      createdAt: "2024-01-01T10:00:00",
      actor: "friend",
      read: read,
      roomId: roomId,
      destinationId: destinationId,
    );

Future<_FakeChat> _openInbox(
  WidgetTester tester, {
  required _FakeSocial social,
  List<ChatRoom> rooms = const [_room],
}) async {
  final chat = _FakeChat(rooms);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedInAuth()),
      ],
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NotificationsScreen(social: social, chat: chat),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return chat;
}

void main() {
  group("Notifications lead somewhere", () {
    testWidgets("tapping a message notification opens that conversation",
        (tester) async {
      final social = _FakeSocial([_notification(id: "n1", roomId: "r1")]);
      await _openInbox(tester, social: social);

      expect(find.byType(ChatRoomScreen), findsNothing);

      await tester.tap(find.text("Amina sent you a message"));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ChatRoomScreen), findsOneWidget,
          reason: "the row must open the thread it is about");

      // Let the room's own poll timer be disposed before the test ends.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("opening a notification marks that one read, not the inbox",
        (tester) async {
      final social = _FakeSocial([
        _notification(id: "n1", roomId: "r1"),
        _notification(id: "n2", roomId: "r1"),
      ]);
      await _openInbox(tester, social: social);

      await tester.tap(find.text("Amina sent you a message").first);
      await tester.pump();
      await tester.pump();

      expect(social.markedRead, ["n1"],
          reason: "reading one message must not clear the rest of the inbox");

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("a notification with no target is not tappable",
        (tester) async {
      // Nothing to open, so the row must not offer a tap that does nothing —
      // a button that silently fails reads as a broken app.
      final social = _FakeSocial([_notification(id: "n1")]);
      await _openInbox(tester, social: social);

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets("a row with a target shows that it leads somewhere",
        (tester) async {
      final social = _FakeSocial([_notification(id: "n1", roomId: "r1")]);
      await _openInbox(tester, social: social);

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets("a conversation that no longer exists says so", (tester) async {
      final social = _FakeSocial([_notification(id: "n1", roomId: "gone")]);
      await _openInbox(tester, social: social, rooms: const [_room]);

      await tester.tap(find.text("Amina sent you a message"));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(find.text("That conversation is no longer available."),
          findsOneWidget,
          reason: "a dead link must explain itself rather than do nothing");
    });
  });
}
