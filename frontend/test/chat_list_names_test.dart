import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/chat_screen.dart";
import "package:globetrotter/services/chat_service.dart";
import "package:globetrotter/utils/chat_wallpaper.dart";
import "package:globetrotter/utils/theme.dart";
import "package:provider/provider.dart";

/// "You can't see the person's name." The name was on screen the whole time,
/// concatenated into the preview line and drawn in the muted secondary brown
/// at the same weight as the message text beside it. Present, and invisible
/// at a glance. These tests pin the name as its own styled span.

class _FakeChatService extends ChatService {
  final List<ChatRoom> rooms;

  _FakeChatService(this.rooms);

  @override
  Future<List<ChatRoom>> fetchRooms(String token) async => rooms;
}

class _SignedInAuth extends AuthProvider {
  @override
  String? get token => "test-token";

  @override
  User? get currentUser =>
      User(id: "u1", username: "me", preferences: const []);
}

ChatRoom _roomWithLast({
  required String username,
  required String displayName,
  required String text,
  bool mine = false,
  bool deleted = false,
}) =>
    ChatRoom(
      id: "r1",
      type: ChatRoomType.direct,
      name: "Amina Nkeng",
      members: const ["me", "friend"],
      otherUsername: "friend",
      lastMessage: ChatMessage(
        id: "m1",
        roomId: "r1",
        username: username,
        displayName: displayName,
        createdAt: "2024-01-01T10:00:00",
        text: text,
        mine: mine,
        deleted: deleted,
      ),
    );

Future<void> _open(WidgetTester tester, List<ChatRoom> rooms) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedInAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.theme,
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatScreen(service: _FakeChatService(rooms)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The rendered styles of the preview line, in order.
List<TextStyle> _previewSpanStyles(WidgetTester tester) {
  final widget = tester.widget<Text>(
    find.byWidgetPredicate(
      (w) => w is Text && w.textSpan != null,
    ),
  );
  final root = widget.textSpan! as TextSpan;
  return [
    for (final child in root.children ?? const <InlineSpan>[])
      if (child is TextSpan) child.style ?? const TextStyle(),
  ];
}

void main() {
  group("The speaker's name is legible in the chat list", () {
    testWidgets("the name is its own span, not glued into the message",
        (tester) async {
      await _open(tester, [
        _roomWithLast(
          username: "friend",
          displayName: "Amina",
          text: "see you at the market",
        ),
      ]);

      final styles = _previewSpanStyles(tester);
      expect(styles, isNotEmpty,
          reason: "the preview must be a rich span, not one flat string");

      final name = styles.first;
      expect(name.fontWeight, FontWeight.w700,
          reason: "the name must carry more weight than the message text");
      expect(name.color, isNot(AppTheme.textSecondary),
          reason: "the muted brown is exactly what made it disappear");
    });

    testWidgets("the name uses the same colour the thread gives that person",
        (tester) async {
      await _open(tester, [
        _roomWithLast(
          username: "friend",
          displayName: "Amina",
          text: "see you at the market",
        ),
      ]);

      expect(_previewSpanStyles(tester).first.color,
          ChatWallpaper.authorColor("friend"),
          reason: "a name learned in the thread should be recognised here");
    });

    testWidgets("your own messages are labelled, and not in someone's colour",
        (tester) async {
      await _open(tester, [
        _roomWithLast(
          username: "me",
          displayName: "Me",
          text: "on my way",
          mine: true,
        ),
      ]);

      expect(find.textContaining("You:"), findsOneWidget);
      expect(_previewSpanStyles(tester).first.color, AppTheme.textPrimary);
    });

    testWidgets("a deleted message shows no speaker", (tester) async {
      // There is no message left to attribute, so a name would be noise.
      await _open(tester, [
        _roomWithLast(
          username: "friend",
          displayName: "Amina",
          text: "gone",
          deleted: true,
        ),
      ]);

      expect(find.textContaining("Amina:"), findsNothing);
      expect(find.textContaining("This message was deleted"), findsOneWidget);
    });

    testWidgets("an account with no display name falls back to its username",
        (tester) async {
      // display_name is optional on the backend, and an empty one used to
      // render a name that was not faint but genuinely absent.
      await _open(tester, [
        _roomWithLast(
          username: "friend",
          displayName: "",
          text: "hello",
        ),
      ]);

      expect(find.textContaining("friend:"), findsOneWidget);
    });

    testWidgets("the room name states its colour rather than inheriting it",
        (tester) async {
      await _open(tester, [
        _roomWithLast(
          username: "friend",
          displayName: "Amina",
          text: "hello",
        ),
      ]);

      final title = tester.widget<Text>(find.text("Amina Nkeng"));
      expect(title.style?.color, AppTheme.textPrimary,
          reason: "who the conversation is with must not depend on an "
              "ancestor getting its text colour right");
    });
  });
}
