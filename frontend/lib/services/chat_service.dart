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
    ChatAttachment? attachment,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/chat/rooms/$roomId/messages"),
          headers: _headers(token, json: true),
          body: jsonEncode({
            "text": text,
            if (replyTo != null) "reply_to": replyTo,
            if (attachment != null) "attachment": attachment.toJson(),
          }),
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

  static String _id(String value) => Uri.encodeComponent(value);

  Future<dynamic> _request(String token, String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final request = http.Request(
        method, Uri.parse("$_base/chat/$path").replace(queryParameters: query));
    request.headers.addAll(_headers(token, json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final client = http.Client();
    try {
      final response = await (() async =>
              http.Response.fromStream(await client.send(request)))()
          .timeout(AppConstants.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _fail(response, "Chat request failed (${response.statusCode})");
      }
      return response.body.isEmpty ? null : jsonDecode(response.body);
    } finally {
      client.close();
    }
  }

  List<ChatMessage> _messages(dynamic data) => (data as List)
      .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
      .toList();
  List<ChatUser> _users(dynamic data) => (data as List)
      .map((e) => ChatUser.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<ChatMessage> editMessage(String token, String id, String text) async =>
      ChatMessage.fromJson(await _request(token, "PATCH", "messages/${_id(id)}",
          body: {"text": text}) as Map<String, dynamic>);

  Future<void> forwardMessage(String token, String id, String roomId) async {
    await _request(token, "POST", "messages/${_id(id)}/forward",
        body: {"room_id": roomId});
  }

  /// Separate from global deletion. The backend must implement /hide;
  /// never fall back to deleting for everyone on an unsupported server.
  Future<void> deleteForMe(String token, String id) async {
    await _request(token, "POST", "messages/${_id(id)}/hide");
  }

  Future<List<ChatMessage>> searchMessages(
          String token, String roomId, String query) async =>
      _messages(await _request(token, "GET", "rooms/${_id(roomId)}/search",
          query: {"q": query}));
  Future<List<ChatMessage>> sharedMedia(String token, String roomId) async =>
      _messages(await _request(token, "GET", "rooms/${_id(roomId)}/media"));
  Future<List<ChatUser>> typing(String token, String roomId) async =>
      _users(await _request(token, "GET", "rooms/${_id(roomId)}/typing"));
  Future<void> announceTyping(String token, String roomId) async {
    await _request(token, "POST", "rooms/${_id(roomId)}/typing");
  }

  Future<ChatRoom> mute(String token, String roomId, bool muted) async =>
      ChatRoom.fromJson(await _request(
          token, "POST", "rooms/${_id(roomId)}/mute",
          body: {"muted": muted}) as Map<String, dynamic>);
  Future<List<ChatUser>> blockedUsers(String token) async =>
      _users(await _request(token, "GET", "blocks"));
  Future<void> block(String token, String username) async {
    await _request(token, "POST", "blocks", body: {"username": username});
  }

  Future<void> unblock(String token, String username) async {
    await _request(token, "DELETE", "blocks/${_id(username)}");
  }

  Future<List<ChatRoom>> discoverGroups(String token, String query) async =>
      (await _request(token, "GET", "groups/discover", query: {"q": query})
              as List)
          .map((e) => ChatRoom.fromJson(e as Map<String, dynamic>))
          .toList();
  Future<ChatRoom> joinByCode(String token, String code) async =>
      ChatRoom.fromJson(await _request(token, "POST", "groups/join",
          body: {"code": code.trim().toUpperCase()}) as Map<String, dynamic>);
  Future<void> requestJoin(String token, String roomId, String message) async {
    await _request(token, "POST", "groups/${_id(roomId)}/requests",
        body: {"message": message});
  }

  Future<List<ChatUser>> groupMembers(String token, String roomId) async =>
      _users(await _request(token, "GET", "groups/${_id(roomId)}/members"));
  Future<List<ChatUser>> joinRequests(String token, String roomId) async =>
      _users(await _request(token, "GET", "groups/${_id(roomId)}/requests"));
  Future<ChatRoom> reviewRequest(
          String token, String roomId, String username, bool approve) async =>
      ChatRoom.fromJson(await _request(
          token, "POST", "groups/${_id(roomId)}/requests/${_id(username)}",
          body: {"approve": approve}) as Map<String, dynamic>);
  Future<ChatRoom> editGroup(String token, String roomId,
          {required String name,
          required String description,
          String? avatarUrl}) async =>
      ChatRoom.fromJson(
          await _request(token, "PATCH", "groups/${_id(roomId)}", body: {
        "name": name,
        "description": description,
        if (avatarUrl != null) "avatar_url": avatarUrl
      }) as Map<String, dynamic>);
  Future<ChatRoom> rotateInvite(String token, String roomId) async {
    final data =
        await _request(token, "POST", "groups/${_id(roomId)}/invite/rotate");
    return ChatRoom.fromJson(data["room"] as Map<String, dynamic>);
  }

  Future<ChatRoom> addMember(
          String token, String roomId, String username) async =>
      ChatRoom.fromJson(await _request(
          token, "POST", "rooms/${_id(roomId)}/members",
          body: {"username": username}) as Map<String, dynamic>);
  Future<ChatRoom> removeMember(
          String token, String roomId, String username) async =>
      ChatRoom.fromJson(await _request(
              token, "DELETE", "groups/${_id(roomId)}/members/${_id(username)}")
          as Map<String, dynamic>);
  Future<ChatRoom> setAdmin(
          String token, String roomId, String username, bool admin) async =>
      ChatRoom.fromJson(await _request(token, admin ? "POST" : "DELETE",
          "groups/${_id(roomId)}/admins${admin ? '' : '/${_id(username)}'}",
          body: admin ? {"username": username} : null) as Map<String, dynamic>);
}
