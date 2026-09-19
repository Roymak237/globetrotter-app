import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/comment.dart";
import "../providers/auth_provider.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";

/// Threaded traveller notes for a destination, with voting.
///
/// Designed to be dropped into the bottom of a detail screen, so it sizes
/// itself to its content rather than expecting a viewport.
class CommentsSection extends StatefulWidget {
  final String destinationId;

  const CommentsSection({super.key, required this.destinationId});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final SocialService _service = SocialService();
  final TextEditingController _input = TextEditingController();

  List<Comment> _comments = const [];
  Comment? _replyTarget;
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token;
    try {
      final comments =
          await _service.fetchComments(widget.destinationId, token: token);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final token = context.read<AuthProvider>().token;
    final text = _input.text.trim();
    if (token == null || text.isEmpty || _posting) return;

    setState(() => _posting = true);
    try {
      await _service.postComment(
        token: token,
        destinationId: widget.destinationId,
        text: text,
        parentId: _replyTarget?.id,
      );
      if (!mounted) return;
      _input.clear();
      setState(() => _replyTarget = null);
      // Refetch so a reply lands in the right place in the tree.
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _vote(Comment comment, int value) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    // Tapping the arrow you already chose clears the vote.
    final next = comment.userVote == value ? 0 : value;
    try {
      await _service.voteComment(
        token: token,
        commentId: comment.id,
        value: next,
      );
      if (mounted) await _load();
    } catch (_) {
      // Voting is incidental; silence keeps the reading flow intact.
    }
  }

  Future<void> _delete(Comment comment) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      await _service.deleteComment(token: token, commentId: comment.id);
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.forum_outlined, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              localizations.commentsTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              localizations.commentsEmpty,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
          )
        else
          for (final comment in _comments)
            _CommentTile(
              comment: comment,
              currentUsername: auth.currentUser?.username,
              onReply: () => setState(() => _replyTarget = comment),
              onVote: (value) => _vote(comment, value),
              onDelete: () => _delete(comment),
              onReplyVote: _vote,
              onReplyDelete: _delete,
            ),
        const SizedBox(height: 16),
        if (auth.isAuthenticated)
          _buildComposer(localizations)
        else
          Text(
            localizations.commentSignInPrompt,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
      ],
    );
  }

  Widget _buildComposer(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replyTarget != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.commentReplyTo
                        .replaceAll("{name}", _replyTarget!.username),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _replyTarget = null),
                  child: const Icon(Icons.close_rounded, size: 16),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: localizations.commentHint,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _posting ? null : _post,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: _posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(localizations.commentPost),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final String? currentUsername;
  final VoidCallback onReply;
  final ValueChanged<int> onVote;
  final VoidCallback onDelete;
  final void Function(Comment, int) onReplyVote;
  final void Function(Comment) onReplyDelete;
  final bool isReply;

  const _CommentTile({
    required this.comment,
    required this.currentUsername,
    required this.onReply,
    required this.onVote,
    required this.onDelete,
    required this.onReplyVote,
    required this.onReplyDelete,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mine = currentUsername != null && comment.username == currentUsername;

    return Padding(
      // Replies are indented so the thread structure is readable at a glance.
      padding: EdgeInsets.only(left: isReply ? 28 : 0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 13 : 16,
                backgroundColor: AppTheme.primarySoft,
                foregroundImage: comment.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(comment.avatarUrl),
                child: Text(
                  comment.username.isEmpty
                      ? "?"
                      : comment.username[0].toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: isReply ? 11 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (comment.isEdited) ...[
                          const SizedBox(width: 6),
                          Text(
                            "· ${localizations.commentEdited}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      comment.text,
                      style: const TextStyle(height: 1.4, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _VoteButton(
                          icon: Icons.keyboard_arrow_up_rounded,
                          active: comment.userVote == 1,
                          onTap: () => onVote(1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            "${comment.score}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: comment.score > 0
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        _VoteButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          active: comment.userVote == -1,
                          onTap: () => onVote(-1),
                        ),
                        const SizedBox(width: 10),
                        if (!isReply)
                          TextButton(
                            onPressed: onReply,
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              localizations.chatReply,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        if (mine)
                          TextButton(
                            onPressed: onDelete,
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              localizations.chatDelete,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final reply in comment.replies)
            _CommentTile(
              comment: reply,
              currentUsername: currentUsername,
              onReply: onReply,
              onVote: (value) => onReplyVote(reply, value),
              onDelete: () => onReplyDelete(reply),
              onReplyVote: onReplyVote,
              onReplyDelete: onReplyDelete,
              isReply: true,
            ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _VoteButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Icon(
        icon,
        size: 20,
        color: active ? AppTheme.primary : AppTheme.textSecondary,
      ),
    );
  }
}
