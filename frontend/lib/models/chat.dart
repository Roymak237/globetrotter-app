// Models for Trip Chat: rooms, messages, reactions and the notification inbox.

class ChatReaction {
  final String emoji;
  final int count;

  /// Whether the viewer is one of the people who reacted.
  final bool reacted;

  const ChatReaction({
    required this.emoji,
    required this.count,
    this.reacted = false,
  });

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
        emoji: json["emoji"]?.toString() ?? "",
        count: (json["count"] as num?)?.toInt() ?? 0,
        reacted: json["reacted"] == true,
      );
}

/// The trimmed quote shown above a reply.
class ReplyPreview {
  final String id;
  final String username;
  final String text;
  final bool deleted;

  const ReplyPreview({
    required this.id,
    required this.username,
    required this.text,
    this.deleted = false,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        id: json["id"]?.toString() ?? "",
        username: json["username"]?.toString() ?? "",
        text: json["text"]?.toString() ?? "",
        deleted: json["deleted"] == true,
      );
}

class ChatMessage {
  final ChatAttachment? attachment;
  final String? editedAt;
  final String? forwardedFrom;
  final String id;
  final String roomId;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String text;
  final String? attachmentUrl;
  final ReplyPreview? replyTo;
  final String createdAt;
  final bool deleted;
  final bool mine;
  final List<ChatReaction> reactions;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.username,
    required this.createdAt,
    this.displayName = "",
    this.avatarUrl = "",
    this.text = "",
    this.attachmentUrl,
    this.replyTo,
    this.deleted = false,
    this.mine = false,
    this.reactions = const [],
    this.attachment,
    this.editedAt,
    this.forwardedFrom,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reply = json["reply_to"];
    final rawReactions = json["reactions"];
    return ChatMessage(
      id: json["id"]?.toString() ?? "",
      roomId: json["room_id"]?.toString() ?? "",
      username: json["username"]?.toString() ?? "",
      displayName: json["display_name"]?.toString() ?? "",
      avatarUrl: json["avatar_url"]?.toString() ?? "",
      text: json["text"]?.toString() ?? "",
      attachmentUrl: json["attachment_url"]?.toString(),
      attachment: json["attachment"] is Map<String, dynamic>
          ? ChatAttachment.fromJson(json["attachment"] as Map<String, dynamic>)
          : json["attachment_url"] is String
              ? ChatAttachment(url: json["attachment_url"] as String)
              : null,
      editedAt: json["edited_at"]?.toString(),
      forwardedFrom: json["forwarded_from"] is Map
          ? (json["forwarded_from"]["display_name"] ??
                  json["forwarded_from"]["username"])
              ?.toString()
          : null,
      replyTo:
          reply is Map<String, dynamic> ? ReplyPreview.fromJson(reply) : null,
      createdAt: json["created_at"]?.toString() ?? "",
      deleted: json["deleted"] == true,
      mine: json["mine"] == true,
      reactions: rawReactions is List
          ? rawReactions
              .whereType<Map<String, dynamic>>()
              .map(ChatReaction.fromJson)
              .toList()
          : const [],
    );
  }
}

enum ChatRoomType { community, group, direct }

class ChatRoom {
  final List<String> admins;
  final bool isAdmin;
  final bool muted;
  final bool blocked;
  final bool requested;
  final String? otherUsername;
  final String? inviteCode;
  final int memberCount;
  final int pendingRequests;
  final String id;
  final ChatRoomType type;
  final String name;
  final String avatarUrl;
  final String description;
  final List<String> members;
  final int unread;
  final ChatMessage? lastMessage;
  final String lastActivity;

  const ChatRoom({
    required this.id,
    required this.type,
    required this.name,
    this.avatarUrl = "",
    this.description = "",
    this.members = const [],
    this.unread = 0,
    this.lastMessage,
    this.lastActivity = "",
    this.admins = const [],
    this.isAdmin = false,
    this.muted = false,
    this.blocked = false,
    this.requested = false,
    this.otherUsername,
    this.inviteCode,
    this.memberCount = 0,
    this.pendingRequests = 0,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final last = json["last_message"];
    final rawMembers = json["members"];
    return ChatRoom(
      id: json["id"]?.toString() ?? "",
      type: switch (json["type"]?.toString()) {
        "community" => ChatRoomType.community,
        "direct" => ChatRoomType.direct,
        _ => ChatRoomType.group,
      },
      name: json["name"]?.toString() ?? "",
      avatarUrl: json["avatar_url"]?.toString() ?? "",
      description: json["description"]?.toString() ?? "",
      members: rawMembers is List
          ? rawMembers.map((e) => e.toString()).toList()
          : const [],
      unread: (json["unread"] as num?)?.toInt() ?? 0,
      lastMessage:
          last is Map<String, dynamic> ? ChatMessage.fromJson(last) : null,
      lastActivity: json["last_activity"]?.toString() ?? "",
      admins: (json["admins"] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      isAdmin: json["is_admin"] == true,
      muted: json["muted"] == true,
      blocked: json["blocked"] == true,
      requested: json["requested"] == true,
      otherUsername: json["other_username"]?.toString(),
      inviteCode: json["invite_code"]?.toString(),
      memberCount: (json["member_count"] as num?)?.toInt() ??
          (rawMembers is List ? rawMembers.length : 0),
      pendingRequests: (json["pending_requests"] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatUser {
  final bool isAdmin;
  final bool isCreator;
  final String bio;
  final String message;
  final String username;
  final String displayName;
  final String avatarUrl;

  const ChatUser({
    required this.username,
    required this.displayName,
    this.avatarUrl = "",
    this.isAdmin = false,
    this.isCreator = false,
    this.bio = "",
    this.message = "",
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        username: json["username"]?.toString() ?? "",
        displayName: json["display_name"]?.toString() ?? "",
        avatarUrl: json["avatar_url"]?.toString() ?? "",
        isAdmin: json["is_admin"] == true,
        isCreator: json["is_creator"] == true,
        bio: json["bio"]?.toString() ?? "",
        message: json["message"]?.toString() ?? "",
      );
}

/// Descriptor returned by the authenticated media upload endpoint.
class ChatAttachment {
  final String url;
  final String kind;
  final String filename;
  final String contentType;
  final int size;
  final int durationMs;

  const ChatAttachment(
      {required this.url,
      this.kind = "file",
      this.filename = "",
      this.contentType = "",
      this.size = 0,
      this.durationMs = 0});

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        url: json["url"]?.toString() ?? "",
        kind: json["kind"]?.toString() ?? "file",
        filename: json["filename"]?.toString() ?? "",
        contentType: json["content_type"]?.toString() ?? "",
        size: (json["size"] as num?)?.toInt() ?? 0,
        durationMs: (json["duration_ms"] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        "url": url,
        "kind": kind,
        "filename": filename,
        "content_type": contentType,
        "size": size,
        "duration_ms": durationMs,
      };
}

class AppNotification {
  final String id;
  final String type;
  final String actor;
  final String text;
  final String createdAt;
  final bool read;
  final String? destinationId;
  final String? roomId;

  const AppNotification({
    required this.id,
    required this.type,
    required this.text,
    required this.createdAt,
    this.actor = "",
    this.read = false,
    this.destinationId,
    this.roomId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json["id"]?.toString() ?? "",
        type: json["type"]?.toString() ?? "",
        actor: json["actor"]?.toString() ?? "",
        text: json["text"]?.toString() ?? "",
        createdAt: json["created_at"]?.toString() ?? "",
        read: json["read"] == true,
        destinationId: json["destination_id"]?.toString(),
        roomId: json["room_id"]?.toString(),
      );
}

/// A community-submitted destination awaiting review.
class Submission {
  final String id;
  final String name;
  final String category;
  final String description;
  final String status;
  final String createdAt;

  const Submission({
    required this.id,
    required this.name,
    required this.status,
    this.category = "",
    this.description = "",
    this.createdAt = "",
  });

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
        id: json["id"]?.toString() ?? "",
        name: json["name"]?.toString() ?? "",
        category: json["category"]?.toString() ?? "",
        description: json["description"]?.toString() ?? "",
        status: json["status"]?.toString() ?? "pending",
        createdAt: json["created_at"]?.toString() ?? "",
      );
}
