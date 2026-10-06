import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/call_service.dart";
import "../services/chat_service.dart";
import "../services/media_service.dart";
import "../utils/chat_wallpaper.dart";
import "../utils/chat_wallpaper_store.dart";
import "../utils/theme.dart";
import "../widgets/chat_media.dart";
import "../widgets/online_badge.dart";

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
  final MediaService _media = MediaService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  ChatMessage? _replyTarget;

  /// Uploaded but not yet sent.
  ///
  /// The file reaches the server as soon as it is chosen, so the wait happens
  /// while the sender is still writing the accompanying note rather than after
  /// they press send. It is only attached to a message when they do.
  ChatAttachment? _attachment;
  bool _uploading = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;
  Timer? _presencePoll;

  /// Members of this room holding an open call socket right now.
  Set<String> _online = const {};

  ChatWallpaper _wallpaper = ChatWallpaper.sand;

  @override
  void initState() {
    super.initState();
    _load();
    _restoreWallpaper();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollNew());
    // Presence changes far less often than messages and only drives a badge,
    // so it is polled at a fifth of the rate rather than riding along with
    // every message fetch.
    _refreshPresence();
    _presencePoll =
        Timer.periodic(const Duration(seconds: 25), (_) => _refreshPresence());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _presencePoll?.cancel();
    _media.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreWallpaper() async {
    final stored = await ChatWallpaperStore.load(widget.room.id);
    if (!mounted || stored == null) return;
    setState(() => _wallpaper = ChatWallpaper.byId(stored));
  }

  /// Refresh the online set.
  ///
  /// The community room has no presence endpoint of its own — asking would
  /// mean publishing the activity of every registered user — so it is skipped
  /// rather than left to 403 on a timer.
  Future<void> _refreshPresence() async {
    if (widget.room.type == ChatRoomType.community) return;
    final token = _token;
    if (token == null) return;
    final online = await _service.presence(token, widget.room.id);
    if (!mounted) return;
    setState(() => _online = online);
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

  /// Pick a file and upload it, holding the result until the message is sent.
  ///
  /// `extensions` narrows the picker to one kind so the platform can open the
  /// gallery for photos rather than a generic file browser.
  Future<void> _attach(List<String> extensions) async {
    final token = _token;
    if (token == null || _uploading || _sending) return;

    setState(() => _uploading = true);
    try {
      final attachment =
          await _media.pickAndUpload(token, extensions: extensions);
      // A null result means the picker was dismissed, which is not a failure
      // and should not leave a message on screen.
      if (!mounted || attachment == null) return;
      setState(() => _attachment = attachment);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst("Exception: ", ""))),
    );
  }

  /// Offer the three kinds the backend accepts.
  Future<void> _showAttachMenu(AppLocalizations localizations) async {
    final choice = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.image_rounded, color: AppTheme.primary),
              title: Text(localizations.chatAttachPhoto),
              onTap: () =>
                  Navigator.pop(sheetContext, MediaService.imageExtensions),
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_rounded, color: AppTheme.primary),
              title: Text(localizations.chatAttachVideo),
              onTap: () =>
                  Navigator.pop(sheetContext, MediaService.videoExtensions),
            ),
            ListTile(
              leading: const Icon(Icons.description_rounded,
                  color: AppTheme.primary),
              title: Text(localizations.chatAttachDocument),
              onTap: () =>
                  Navigator.pop(sheetContext, MediaService.documentExtensions),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice != null) await _attach(choice);
  }

  Future<void> _send() async {
    final token = _token;
    final text = _input.text.trim();
    final attachment = _attachment;
    // An attachment is a message in its own right, so an empty box is only a
    // reason to stop when there is nothing attached either.
    if (token == null || (text.isEmpty && attachment == null) || _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      final message = await _service.sendMessage(
        token: token,
        roomId: widget.room.id,
        text: text,
        replyTo: _replyTarget?.id,
        attachment: attachment,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, message];
        _replyTarget = null;
        _attachment = null;
        _input.clear();
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
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
        title: _buildTitle(title),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        actions: [..._callActions(), _wallpaperMenu()],
      ),
      body: Column(
        children: [
          // The wallpaper sits behind the thread only. Running it behind the
          // composer too would put a tinted gradient under a text field and
          // make the caret and hint harder to read for no gain.
          Expanded(
            child: DecoratedBox(
              decoration: _wallpaper.decoration,
              child: _buildMessages(localizations),
            ),
          ),
          if (_replyTarget != null) _buildReplyBanner(localizations),
          _buildComposer(localizations),
        ],
      ),
    );
  }

  /// Room name, plus a live "Online" line when someone is actually reachable.
  Widget _buildTitle(String title) {
    final anyoneOnline = _online.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
        if (anyoneOnline) ...[
          const SizedBox(width: 8),
          // Bordered in the app bar's own tone rather than white, so the ring
          // reads as separation from the gradient behind it.
          const OnlineDot(online: true, borderColor: Color(0x33FFFFFF)),
        ],
      ],
    );
  }

  Widget _wallpaperMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.wallpaper_rounded),
      tooltip: "Wallpaper",
      onSelected: _applyWallpaper,
      itemBuilder: (context) => [
        for (final wallpaper in ChatWallpaper.presets)
          PopupMenuItem<String>(
            value: wallpaper.id,
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: wallpaper.decoration.gradient,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 10),
                Text(wallpaper.label),
                if (wallpaper.id == _wallpaper.id) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded,
                      size: 17, color: AppTheme.primary),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _applyWallpaper(String id) async {
    setState(() => _wallpaper = ChatWallpaper.byId(id));
    await ChatWallpaperStore.save(widget.room.id, id);
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
                  token: _token,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachment != null) _buildAttachmentChip(localizations),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Disabled rather than hidden while an upload is in flight, so
                // the row does not reflow under the thumb mid-tap.
                IconButton(
                  onPressed: _uploading || _sending
                      ? null
                      : () => _showAttachMenu(localizations),
                  tooltip: localizations.chatAttach,
                  icon: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        )
                      : const Icon(Icons.attach_file_rounded),
                  color: AppTheme.primary,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: localizations.chatMessageHint,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
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
          ],
        ),
      ),
    );
  }

  /// Confirms what is about to be sent, and offers a way out.
  ///
  /// Without this the only evidence of a successful upload would be the
  /// message that appears after sending, which is too late to discover the
  /// wrong file was picked.
  Widget _buildAttachmentChip(AppLocalizations localizations) {
    final attachment = _attachment!;
    final label = attachment.filename.trim().isEmpty
        ? localizations.chatAttachment
        : attachment.filename;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: AppTheme.primary),
      ),
      child: Row(
        children: [
          Icon(_attachmentIcon(attachment.kind),
              size: 18, color: AppTheme.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
          IconButton(
            onPressed:
                _sending ? null : () => setState(() => _attachment = null),
            tooltip: localizations.chatAttachRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.primaryDark,
          ),
        ],
      ),
    );
  }

  static IconData _attachmentIcon(String kind) => switch (kind) {
        "image" => Icons.image_rounded,
        "video" => Icons.videocam_rounded,
        "audio" => Icons.graphic_eq_rounded,
        _ => Icons.description_rounded,
      };
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

  /// Needed to fetch attachment bytes, which are served behind auth.
  /// Null only in the moment between sign-out and the screen being popped.
  final String? token;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onReactionTap;

  const _MessageBubble({
    required this.message,
    required this.showAuthor,
    required this.onReactionTap,
    this.token,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mine = message.mine;
    // A deleted message keeps its row but loses its contents, attachment
    // included, so the file is not still fetchable from a tombstone.
    final attachment = message.deleted ? null : message.attachment;

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
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    // Falling back to the username matters: display_name is
                    // optional on the backend, and an account without one used
                    // to render an empty string here — a name that was not
                    // merely faint but genuinely absent.
                    message.displayName.trim().isEmpty
                        ? message.username
                        : message.displayName,
                    style: TextStyle(
                      // Was 11px in the muted secondary brown, which put the
                      // speaker's name at the same visual weight as a
                      // timestamp and let it disappear into the background.
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                      color: ChatWallpaper.authorColor(message.username),
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
                      if (attachment != null && token != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ChatAttachmentView(
                            attachment: attachment,
                            token: token!,
                          ),
                        ),
                        // Only pad away from the caption when there is one.
                        if (message.text.isNotEmpty) const SizedBox(height: 6),
                      ],
                      // An attachment can travel without a caption, and an
                      // empty Text would still claim a line of height and open
                      // a gap under the picture.
                      if (message.text.isNotEmpty || message.deleted)
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
        // Incoming bubbles are `indigoSoft`, so the quote needs its own
        // surface to read as inset. It used pure white, which separated only
        // by being colder than everything around it.
        color: mine ? Colors.white24 : AppTheme.surfaceSunken,
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
