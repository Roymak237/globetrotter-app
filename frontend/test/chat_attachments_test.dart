import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/localization/app_localizations.dart";
import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/user.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:globetrotter/screens/chat_room_screen.dart";
import "package:globetrotter/services/chat_service.dart";
import "package:globetrotter/utils/theme.dart";
import "package:globetrotter/widgets/chat_media.dart";
import "package:provider/provider.dart";

/// Sending a picture, a video or a document was built end to end — the upload
/// endpoint, the attachment model, the viewer widget — and then left with no
/// way to reach it: the composer had a text field and a send button and
/// nothing else, and the bubble rendered only `message.text`. These tests
/// cover the two halves of that gap.

class _FakeChatService extends ChatService {
  final List<ChatMessage> tail;

  _FakeChatService({this.tail = const []});

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? since,
  }) async =>
      since == null ? tail : const [];

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

ChatMessage _message({
  String text = "",
  ChatAttachment? attachment,
  bool deleted = false,
}) =>
    ChatMessage(
      id: "m1",
      roomId: "r1",
      username: "friend",
      createdAt: "2024-01-01T10:00:00",
      text: text,
      attachment: attachment,
      deleted: deleted,
    );

/// A document rather than an image on purpose: the viewer only reaches for the
/// network when it has a picture to decode, so this exercises the rendering
/// path without a fake HTTP client.
const ChatAttachment _document = ChatAttachment(
  url: "/api/media/abc123.pdf",
  kind: "file",
  filename: "itinerary.pdf",
  contentType: "application/pdf",
  size: 4096,
);

Future<void> _open(WidgetTester tester,
    {List<ChatMessage> tail = const []}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedInAuth()),
      ],
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatRoomScreen(
          room: _room,
          service: _FakeChatService(tail: tail),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group("Attachments can be sent", () {
    testWidgets("the composer offers a way to attach a file", (tester) async {
      await _open(tester);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget,
          reason: "without this the upload path is unreachable");
      await _close(tester);
    });

    testWidgets("the attach menu offers photos, videos and documents",
        (tester) async {
      await _open(tester);

      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();

      expect(find.text("Photo"), findsOneWidget);
      expect(find.text("Video"), findsOneWidget);
      expect(find.text("Document (PDF)"), findsOneWidget);

      // Dismiss the sheet so the screen can be torn down cleanly.
      Navigator.of(tester.element(find.text("Photo"))).pop();
      await tester.pumpAndSettle();
      await _close(tester);
    });
  });

  group("Attachments can be seen", () {
    testWidgets("a message carrying a file renders it", (tester) async {
      await _open(tester, tail: [_message(attachment: _document)]);

      expect(find.byType(ChatAttachmentView), findsOneWidget);
      expect(find.text("itinerary.pdf"), findsOneWidget);
      await _close(tester);
    });

    testWidgets("a caption sits alongside the file, not instead of it",
        (tester) async {
      await _open(tester,
          tail: [_message(text: "Here it is", attachment: _document)]);

      expect(find.byType(ChatAttachmentView), findsOneWidget);
      expect(find.text("Here it is"), findsOneWidget);
      await _close(tester);
    });

    testWidgets("a deleted message keeps no attachment behind it",
        (tester) async {
      // The tombstone must not stay a working download link.
      await _open(tester,
          tail: [_message(attachment: _document, deleted: true)]);

      expect(find.byType(ChatAttachmentView), findsNothing);
      expect(find.text("itinerary.pdf"), findsNothing);
      await _close(tester);
    });
  });

  group("Surfaces are warm, not clinical", () {
    test("the shared surface colour is not pure white", () {
      // The complaint was that the app read as "too white". Every card, tile,
      // input and chip takes its background from here, so a regression to
      // Colors.white would undo the fix everywhere at once.
      expect(AppTheme.surface, isNot(Colors.white));

      // Still lighter than the page, or cards would dissolve into it.
      int luminance(Color c) => ((c.r + c.g + c.b) * 255 / 3).round();
      expect(luminance(AppTheme.surface),
          greaterThan(luminance(AppTheme.background)));

      // And still warm: the ochre end must outweigh the blue end, which is
      // exactly what pure white fails to do.
      expect(AppTheme.surface.r, greaterThan(AppTheme.surface.b));
    });
  });
}
