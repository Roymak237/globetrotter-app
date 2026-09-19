import "dart:convert";

import "package:globetrotter/models/chat.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;

/// Trip Chat transport.
///
/// The backend is poll-based rather than websocket-based, so [fetchMessages]
/// accepts a `since` cursor and callers re-poll on a timer.
class ChatService {
  final String _base =
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}";

  /// Id of the room every signed-in traveller shares.
  static const String communityRoomId = "community";

  Map<String, String> _headers(String token, {bool json = false}) => {
        "Authorization": "Bearer $token",
        if (json) "Content-Type": "application/json",
      };

  Never _fail(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body["error"] != null) {
        throw Exception(body["error"].toString());
      }
    } on FormatException {
      // Body was not JSON; fall through to the generic message below.
    }
    throw Exception(fallback);
  }

  Future<List<ChatRoom>> fetchRooms(String token) async {
    final response = await http
        .get(
          Uri.parse("$_base/chat/rooms"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatRoom.fromJson)
          .toList();
    }
    _fail(response, "Could not load your chats");
  }

  Future<ChatRoom> createGroup({
    required String token,
    required String name,
    String description = "",
    List<String> members = const [],
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/rooms"),
          headers: _headers(token, json: true),
          body: jsonEncode({
            "name": name,
            "description": description,
            "members": members,
          }),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 201) {
      return ChatRoom.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not create the group");
  }

  /// Opens the conversation with [username], reusing it when one already exists.
  Future<ChatRoom> openDirect({
    required String token,
    required String username,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/direct"),
          headers: _headers(token, json: true),
          body: jsonEncode({"username": username}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return ChatRoom.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not open the conversation");
  }

  /// Omitting [since] returns the tail of the room; passing it returns only
  /// messages newer than that timestamp.
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? since,
  }) async {
    final uri = Uri.parse("$_base/chat/rooms/$roomId/messages").replace(
      queryParameters: since == null ? null : {"since": since},
    );
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    }
    _fail(response, "Could not load messages");
  }

  Future<ChatMessage> sendMessage({
    required String token,
    required String roomId,
    required String text,
    String? replyTo,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/rooms/$roomId/messages"),
          headers: _headers(token, json: true),
          body: jsonEncode(
              {"text": text, if (replyTo != null) "reply_to": replyTo}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 201) {
      return ChatMessage.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not send your message");
  }

  Future<void> markRead({required String token, required String roomId}) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/rooms/$roomId/read"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not update the room");
    }
  }

  /// Adds the reaction, or removes it when the viewer already reacted with it.
  Future<ChatMessage> toggleReaction({
    required String token,
    required String messageId,
    required String emoji,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/messages/$messageId/reactions"),
          headers: _headers(token, json: true),
          body: jsonEncode({"emoji": emoji}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return ChatMessage.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not react to the message");
  }

  Future<void> deleteMessage({
    required String token,
    required String messageId,
  }) async {
    final response = await http
        .delete(
          Uri.parse("$_base/chat/messages/$messageId"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not delete the message");
    }
  }

  Future<List<ChatUser>> searchUsers({
    required String token,
    required String query,
  }) async {
    final uri = Uri.parse("$_base/chat/users/search")
        .replace(queryParameters: {"q": query});
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatUser.fromJson)
          .toList();
    }
    _fail(response, "Could not search for people");
  }

  Future<void> leaveGroup(
      {required String token, required String roomId}) async {
    final response = await http
        .delete(
          Uri.parse("$_base/chat/rooms/$roomId/members"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not leave the group");
    }
  }
}
