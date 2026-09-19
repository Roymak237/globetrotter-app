// Models for the community layer: threaded comments and app reviews.

class Comment {
  final String id;
  final String destinationId;
  final String? parentId;
  final String username;
  final String avatarUrl;
  final String text;
  final String createdAt;
  final String? editedAt;
  final int score;

  /// The viewer's own vote: 1, -1, or null when they have not voted.
  final int? userVote;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.destinationId,
    required this.username,
    required this.text,
    required this.createdAt,
    this.parentId,
    this.avatarUrl = "",
    this.editedAt,
    this.score = 0,
    this.userVote,
    this.replies = const [],
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final rawReplies = json["replies"];
    return Comment(
      id: json["id"]?.toString() ?? "",
      destinationId: json["destination_id"]?.toString() ?? "",
      parentId: json["parent_id"]?.toString(),
      username: json["username"]?.toString() ?? "",
      avatarUrl: json["avatar_url"]?.toString() ?? "",
      text: json["text"]?.toString() ?? "",
      createdAt: json["created_at"]?.toString() ?? "",
      editedAt: json["edited_at"]?.toString(),
      score: (json["score"] as num?)?.toInt() ?? 0,
      userVote: (json["user_vote"] as num?)?.toInt(),
      replies: rawReplies is List
          ? rawReplies
              .whereType<Map<String, dynamic>>()
              .map(Comment.fromJson)
              .toList()
          : const [],
    );
  }

  bool get isEdited => editedAt != null && editedAt!.isNotEmpty;
}

class AppReview {
  final String username;
  final String avatarUrl;
  final int stars;
  final String? feedback;
  final String createdAt;

  const AppReview({
    required this.username,
    required this.stars,
    this.avatarUrl = "",
    this.feedback,
    this.createdAt = "",
  });

  factory AppReview.fromJson(Map<String, dynamic> json) => AppReview(
        username: json["username"]?.toString() ?? "",
        avatarUrl: json["avatar_url"]?.toString() ?? "",
        stars: (json["stars"] as num?)?.toInt() ?? 0,
        feedback: json["feedback"]?.toString(),
        createdAt: json["created_at"]?.toString() ?? "",
      );
}

/// The aggregate rating plus the most recent written reviews.
class AppReviewSummary {
  final double average;
  final int count;
  final AppReview? mine;
  final List<AppReview> reviews;

  const AppReviewSummary({
    this.average = 0,
    this.count = 0,
    this.mine,
    this.reviews = const [],
  });

  factory AppReviewSummary.fromJson(Map<String, dynamic> json) {
    final mine = json["mine"];
    final list = json["reviews"];
    return AppReviewSummary(
      average: (json["average"] as num?)?.toDouble() ?? 0,
      count: (json["count"] as num?)?.toInt() ?? 0,
      mine: mine is Map<String, dynamic> ? AppReview.fromJson(mine) : null,
      reviews: list is List
          ? list
              .whereType<Map<String, dynamic>>()
              .map(AppReview.fromJson)
              .toList()
          : const [],
    );
  }
}
