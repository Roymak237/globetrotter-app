import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/call_service.dart";
import "../services/chat_service.dart";
import "../utils/theme.dart";

/// A single conversation. Polls for new messages with a `since` cursor so the
/// thread stays current without holding a socket open.
class ChatRoomScreen extends StatefulWidget {
  final ChatRoom room;

  /// Transport override, for tests only.
  ///
  /// [ChatService] reaches for the top-level `http` functions rather than an
  /// injected client, so there is no other seam to fake the network through.
  /// Production always leaves this null and gets the real service.
  @visibleForTesting
  final ChatService? service;

  const ChatRoomScreen({super.key, required this.room, this.service});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static const List<String> _quickReactions = ["👍", "❤️", "😂", "🔥", "🙏"];

  late final ChatService _service = widget.service ?? ChatService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  ChatMessage? _replyTarget;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  /// Cursor for an incremental fetch, or null when we hold nothing yet.
  ///
  /// Messages are kept oldest-first, so the newest `created_at` is the last
  /// one. Returning null asks the backend for the tail instead, which is
  /// exactly what an empty room needs.
  String? get _cursor => _messages.isEmpty ? null : _messages.last.createdAt;

  /// True when the view is already parked at the newest message.
  ///
  /// A background refresh should not yank the list away from someone reading
  /// back through history, so only auto-scroll when they were at the bottom
  /// to begin with.
  bool get _isAtBottom {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    return position.maxScrollExtent - position.pixels < 120;
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final messages =
          await _service.fetchMessages(token: token, roomId: widget.room.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
      unawaited(_service.markRead(token: token, roomId: widget.room.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  /// Pull in whatever arrived since our newest message.
  ///
  /// This deliberately does *not* bail out when the thread is empty. It used
  /// to, and that early return left an empty room permanently stale: with no
  /// message to build a cursor from, every later tick stopped at the same
  /// guard, so a conversation opened before the first reply landed never
  /// updated again. Closing and reopening the screen was the only way to see
  /// anything, which is why it looked as though you had to sign out and back
  /// in to read new messages. With no cursor we ask for the tail instead.
  Future<void> _pollNew() async {
    final token = _token;
    if (token == null) return;
    try {
      final fresh = await _service.fetchMessages(
        token: token,
        roomId: widget.room.id,
        since: _cursor,
      );
      if (!mounted || fresh.isEmpty) return;
      final wasAtBottom = _isAtBottom;
      setState(() => _messages = _merge(_messages, fresh));
      if (wasAtBottom) _scrollToBottom();
      unawaited(_service.markRead(token: token, roomId: widget.room.id));
    } catch (_) {
      // Transient failures are ignored; the next tick retries.
    }
  }

  /// Append [fresh] to [current], skipping ids we already hold.
  ///
  /// The `since` filter is exclusive, so an incremental fetch cannot normally
  /// overlap what we have. A cursorless fetch can, though, and so can a send
  /// that lands between reading the cursor and applying the response, so
  /// dedupe rather than assume.
  static List<ChatMessage> _merge(
    List<ChatMessage> current,
    List<ChatMessage> fresh,
  ) {
    final seen = current.map((message) => message.id).toSet();
    return [...current, ...fresh.where((message) => seen.add(message.id))];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final token = _token;
    final text = _input.text.trim();
    if (token == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final message = await _service.sendMessage(
        token: token,
        roomId: widget.room.id,
        text: text,
        replyTo: _replyTarget?.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, message];
        _replyTarget = null;
        _input.clear();
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(ChatMessage message, String emoji) async {
    final token = _token;
    if (token == null) return;
    try {
      final updated = await _service.toggleReaction(
        token: token,
        messageId: message.id,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          for (final m in _messages) m.id == updated.id ? updated : m,
        ];
      });
    } catch (_) {
      // Reacting is incidental; a failure does not warrant interrupting.
    }
  }

  Future<void> _delete(ChatMessage message) async {
    final token = _token;
    if (token == null) return;
    try {
      await _service.deleteMessage(token: token, messageId: message.id);
      if (!mounted) return;
      setState(() {
        _messages = [
          for (final m in _messages)
            if (m.id != message.id) m,
        ];
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    }
  }

  void _showMessageActions(ChatMessage message) {
    final localizations = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _quickReactions)
                    IconButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _react(message, emoji);
                      },
                      icon: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(localizations.chatReply),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _replyTarget = message);
              },
            ),
            if (message.mine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                title: Text(
                  localizations.chatDelete,
                  style: const TextStyle(color: AppTheme.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _delete(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Call buttons, shown only where a call makes sense.
  ///
  /// The community room is excluded because ringing every registered traveller
  /// is never the intent, and a room with nobody else has no one to ring.
  List<Widget> _callActions() {
    if (widget.room.type == ChatRoomType.community) return const [];

    final me = context.read<AuthProvider>().currentUser?.username;
    final peer = widget.room.otherUsername ??
        widget.room.members.firstWhere(
          (member) => member != me,
          orElse: () => "",
        );
    if (peer.isEmpty) return const [];

    final localizations = AppLocalizations.of(context);
    return [
      _CallAction(
        tooltip: localizations.chatVoiceCall,
        icon: Icons.call_rounded,
        onPressed: () => _startCall(peer, video: false),
      ),
      _CallAction(
        tooltip: localizations.chatVideoCall,
        icon: Icons.videocam_rounded,
        onPressed: () => _startCall(peer, video: true),
      ),
      const SizedBox(width: 4),
    ];
  }

  Future<void> _startCall(String peer, {required bool video}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) return;

    final calls = context.read<CallService>();
    await calls.connect(token, auth.currentUser?.username ?? "");
    await calls.startCall(
      roomId: widget.room.id,
      peer: peer,
      peerDisplayName: widget.room.name,
      video: video,
    );
    if (!mounted) return;
    Navigator.pushNamed(context, "/call");
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final title = widget.room.type == ChatRoomType.community
        ? localizations.chatCommunityRoom
        : widget.room.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        actions: _callActions(),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages(localizations)),
          if (_replyTarget != null) _buildReplyBanner(localizations),
          _buildComposer(localizations),
        ],
      ),
    );
  }

  Widget _buildMessages(AppLocalizations localizations) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    // Pull to refresh sits on top of the five-second poll. The poll handles
    // the common case, but an explicit gesture is what people reach for when
    // they suspect they are looking at something stale, and it costs one
    // request.
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      child: _error != null || _messages.isEmpty
          ? _buildPlaceholder(localizations)
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                // Only label the first message in a run from the same person.
                final previous = index == 0 ? null : _messages[index - 1];
                final showAuthor =
                    previous == null || previous.username != message.username;
                return _MessageBubble(
                  message: message,
                  showAuthor: showAuthor && !message.mine,
                  onLongPress: message.deleted
                      ? null
                      : () => _showMessageActions(message),
                  onReactionTap: (emoji) => _react(message, emoji),
                );
              },
            ),
    );
  }

  /// Reload the tail and clear any stale error.
  Future<void> _refresh() async {
    if (mounted) setState(() => _error = null);
    await _load();
  }

  /// The empty and error states, made scrollable so the pull gesture still
  /// works. A bare `Center` cannot be dragged, which would withhold refresh in
  /// exactly the two states where someone is most likely to want it.
  Widget _buildPlaceholder(AppLocalizations localizations) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _error != null
                  ? Text(_error!, textAlign: TextAlign.center)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 48, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          localizations.chatNoMessages,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          localizations.chatStartConversation,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBanner(AppLocalizations localizations) {
    final target = _replyTarget!;
    return Container(
      color: AppTheme.primarySoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.chatReply,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  target.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _replyTarget = null),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(AppLocalizations localizations) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: localizations.chatMessageHint,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A call button that carries its own dark backing.
///
/// The app bar gradient runs `primaryDark → primary → clay → secondary` from
/// left to right, and `AppBar.actions` render at the right-hand end. White
/// icons on that amber `secondary` measure roughly 2.67:1, under the 3:1 that
/// WCAG asks for on interface icons. That is why these two buttons were
/// reported as hard to make out while the title, sitting over the dark left
/// end at about 9:1, read perfectly well. Painting a solid `primaryDark` disc
/// behind each icon pins the contrast near 9.4:1 wherever the gradient
/// happens to fall, and reads as a deliberate action chip rather than an
/// accident of the background.
class _CallAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CallAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: Material(
        color: AppTheme.primaryDark,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          iconSize: 20,
          padding: EdgeInsets.zero,
          color: Colors.white,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAuthor;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onReactionTap;

  const _MessageBubble({
    required this.message,
    required this.showAuthor,
    required this.onReactionTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mine = message.mine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showAuthor)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 3),
                  child: Text(
                    message.displayName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    // Outgoing borrows the brand terracotta; incoming uses the
                    // cool indigo tint so the two never read as the same voice.
                    color: mine ? AppTheme.primary : AppTheme.indigoSoft,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyTo != null) _replyQuote(mine),
                      Text(
                        message.deleted
                            ? localizations.chatDeleted
                            : message.text,
                        style: TextStyle(
                          color: mine ? Colors.white : AppTheme.textPrimary,
                          fontStyle: message.deleted
                              ? FontStyle.italic
                              : FontStyle.normal,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (message.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final reaction in message.reactions)
                        InkWell(
                          onTap: () => onReactionTap(reaction.emoji),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: reaction.reacted
                                  ? AppTheme.primarySoft
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: reaction.reacted
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              "${reaction.emoji} ${reaction.count}",
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyQuote(bool mine) {
    final quote = message.replyTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: mine ? Colors.white24 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: mine ? Colors.white : AppTheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote.username,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: mine ? Colors.white : AppTheme.primary,
            ),
          ),
          Text(
            quote.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: mine ? Colors.white70 : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
