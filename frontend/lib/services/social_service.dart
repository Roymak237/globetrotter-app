import "dart:convert";

import "package:globetrotter/models/chat.dart";
import "package:globetrotter/models/comment.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;

/// Calls for the community layer, the notification inbox and Trip Chat.
///
/// Every method takes the caller's token explicitly rather than reading a
/// global, which keeps the service stateless and trivial to test.
class SocialService {
  final String _base =
      "${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}";

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

  // ------------------------------------------------------------- comments

  Future<List<Comment>> fetchComments(String destinationId,
      {String? token}) async {
    final response = await http
        .get(
          Uri.parse("$_base/destinations/$destinationId/comments"),
          headers: token == null ? null : _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(Comment.fromJson)
          .toList();
    }
    _fail(response, "Could not load comments");
  }

  Future<Comment> postComment({
    required String token,
    required String destinationId,
    required String text,
    String? parentId,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/destinations/$destinationId/comments"),
          headers: _headers(token, json: true),
          body: jsonEncode(
              {"text": text, if (parentId != null) "parent_id": parentId}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 201) {
      return Comment.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not post your comment");
  }

  Future<void> deleteComment(
      {required String token, required String commentId}) async {
    final response = await http
        .delete(
          Uri.parse("$_base/comments/$commentId"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not delete your comment");
    }
  }

  /// [value] is 1, -1, or 0 to clear the viewer's existing vote.
  Future<Comment> voteComment({
    required String token,
    required String commentId,
    required int value,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/comments/$commentId/vote"),
          headers: _headers(token, json: true),
          body: jsonEncode({"value": value}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return Comment.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not record your vote");
  }

  // --------------------------------------------------------- app reviews

  Future<AppReviewSummary> fetchAppReviews({String? token}) async {
    final response = await http
        .get(
          Uri.parse("$_base/app-reviews"),
          headers: token == null ? null : _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      return AppReviewSummary.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _fail(response, "Could not load reviews");
  }

  Future<void> submitAppReview({
    required String token,
    required int stars,
    String? feedback,
  }) async {
    final response = await http
        .put(
          Uri.parse("$_base/app-reviews"),
          headers: _headers(token, json: true),
          body: jsonEncode({"stars": stars, "feedback": feedback ?? ""}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not save your review");
    }
  }

  // ----------------------------------------------------------- interests

  /// Returns the viewer's chosen interests and the full vocabulary to pick from.
  Future<({List<String> interests, List<String> available})> fetchInterests(
    String token,
  ) async {
    final response = await http
        .get(
          Uri.parse("$_base/me/interests"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        interests: (body["interests"] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        available: (body["available"] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
    }
    _fail(response, "Could not load your interests");
  }

  Future<List<String>> saveInterests({
    required String token,
    required List<String> interests,
  }) async {
    final response = await http
        .put(
          Uri.parse("$_base/me/interests"),
          headers: _headers(token, json: true),
          body: jsonEncode({"interests": interests}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body["interests"] as List? ?? [])
          .map((e) => e.toString())
          .toList();
    }
    _fail(response, "Could not save your interests");
  }

  // ------------------------------------------------------- notifications

  Future<({int unread, List<AppNotification> items})> fetchNotifications(
    String token,
  ) async {
    final response = await http
        .get(
          Uri.parse("$_base/me/notifications"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body["notifications"] as List? ?? [];
      return (
        unread: (body["unread"] as num?)?.toInt() ?? 0,
        items: list
            .whereType<Map<String, dynamic>>()
            .map(AppNotification.fromJson)
            .toList(),
      );
    }
    _fail(response, "Could not load notifications");
  }

  /// Passing no ids marks the whole inbox read.
  Future<void> markNotificationsRead({
    required String token,
    List<String>? ids,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/me/notifications/read"),
          headers: _headers(token, json: true),
          body: jsonEncode({if (ids != null) "ids": ids}),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode != 200) {
      _fail(response, "Could not update notifications");
    }
  }

  // --------------------------------------------------------- submissions

  Future<List<Submission>> fetchMySubmissions(String token) async {
    final response = await http
        .get(
          Uri.parse("$_base/me/submissions"),
          headers: _headers(token),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(Submission.fromJson)
          .toList();
    }
    _fail(response, "Could not load your submissions");
  }

  Future<Submission> submitDestination({
    required String token,
    required String name,
    String category = "",
    String description = "",
    String address = "",
    double? latitude,
    double? longitude,
  }) async {
    final response = await http
        .post(
          Uri.parse("$_base/destinations/submit"),
          headers: _headers(token, json: true),
          body: jsonEncode({
            "name": name,
            "category": category,
            "description": description,
            "address": address,
            if (latitude != null) "latitude": latitude,
            if (longitude != null) "longitude": longitude,
          }),
        )
        .timeout(AppConstants.apiTimeout);

    if (response.statusCode == 201) {
      return Submission.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _fail(response, "Could not send your suggestion");
  }
}
