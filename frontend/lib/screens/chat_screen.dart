import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/chat_service.dart";
import "../utils/chat_wallpaper.dart";
import "../utils/media_url.dart";
import "../utils/theme.dart";
import "../widgets/online_badge.dart";
import "../widgets/state_views.dart";
import "chat_room_screen.dart";

/// The Trip Chat landing surface: the shared community room plus every direct
/// conversation and group the traveller belongs to.
class ChatScreen extends StatefulWidget {
  /// When false the screen renders bare, for embedding inside the home shell.
  final bool showScaffold;

  /// Transport override, for tests only.
  ///
  /// [ChatService] reaches for the top-level `http` functions rather than an
  /// injected client, so there is no other seam to fake the network through.
  /// Production always leaves this null and gets the real service.
  @visibleForTesting
  final ChatService? service;

  const ChatScreen({super.key, this.showScaffold = true, this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _service = widget.service ?? ChatService();

  List<ChatRoom> _rooms = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh unread badges periodically. The interval is deliberately long:
    // the room list only needs to feel current, not instant.
    _poll =
        Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _load({bool quiet = false}) async {
    final token = _token;
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!quiet && mounted) setState(() => _loading = true);

    try {
      final rooms = await _service.fetchRooms(token);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed background poll should never replace content already on
      // screen with an error page.
      setState(() {
        _loading = false;
        if (!quiet) _error = error.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatRoomScreen(room: room)),
    );
    if (mounted) _load(quiet: true);
  }

  Future<void> _startDirectMessage() async {
    final token = _token;
    if (token == null) return;

    final picked = await showModalBottomSheet<ChatUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserSearchSheet(service: _service, token: token),
    );
    if (picked == null || !mounted) return;

    try {
      final room =
          await _service.openDirect(token: token, username: picked.username);
      if (!mounted) return;
      await _openRoom(room);
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
    final body = _buildBody(localizations);

    if (!widget.showScaffold) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: body,
        floatingActionButton: _fab(localizations),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.chatHeading),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
      ),
      body: body,
      floatingActionButton: _fab(localizations),
    );
  }

  Widget _fab(AppLocalizations localizations) => FloatingActionButton.extended(
        onPressed: _startDirectMessage,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_search_rounded),
        label: Text(localizations.chatFindPeople),
      );

  Widget _buildBody(AppLocalizations localizations) {
    if (_loading && _rooms.isEmpty) {
      return AppLoadingView(message: localizations.chatHeading);
    }
    if (_error != null && _rooms.isEmpty) {
      return ErrorStateView(
        title: localizations.chatHeading,
        message: _error!,
        onRetry: _load,
      );
    }
    if (_rooms.isEmpty) {
      return EmptyStateView(
        icon: Icons.forum_outlined,
        title: localizations.chatEmptyTitle,
        message: localizations.chatEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _RoomTile(
          room: _rooms[index],
          onTap: () => _openRoom(_rooms[index]),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;

  const _RoomTile({required this.room, required this.onTap});

  IconData get _icon => switch (room.type) {
        ChatRoomType.community => Icons.public_rounded,
        ChatRoomType.group => Icons.groups_rounded,
        ChatRoomType.direct => Icons.person_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final last = room.lastMessage;

    // The sender's name used to be concatenated into the preview string and
    // drawn in the same muted brown as the message text, at the same weight.
    // It was present and unreadable at a glance, which is what "you can't see
    // the person's name" meant. Keeping it as a separate span lets it carry
    // its own weight and colour.
    final speaker = last == null || last.deleted
        ? ""
        : last.mine
            ? localizations.chatYou
            : (last.displayName.trim().isEmpty
                ? last.username
                : last.displayName);
    final preview = last == null
        ? room.description
        : last.deleted
            ? localizations.chatDeleted
            : last.text;

    // Reusing the thread's own palette means a name learned inside a
    // conversation is recognised at a glance in the list.
    final speakerColor = last == null || last.mine
        ? AppTheme.textPrimary
        : ChatWallpaper.authorColor(last.username);

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              OnlineBadge(
                online: room.online,
                dotSize: 14,
                // The ring separates the dot from the tile behind it, so it
                // matches the tile rather than the page.
                borderColor: AppTheme.surface,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: room.type == ChatRoomType.community
                      ? AppTheme.primarySoft
                      : AppTheme.indigoSoft,
                  foregroundImage: resolveMediaUrl(room.avatarUrl).isEmpty
                      ? null
                      : NetworkImage(resolveMediaUrl(room.avatarUrl)),
                  child: Icon(
                    _icon,
                    color: room.type == ChatRoomType.community
                        ? AppTheme.primary
                        : AppTheme.indigo,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.type == ChatRoomType.community
                          ? localizations.chatCommunityRoom
                          : room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            // Stated outright rather than inherited. Who the
                            // conversation is with is the most important thing
                            // on this row and must not depend on an ancestor
                            // getting its text colour right.
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (preview.isNotEmpty || speaker.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (speaker.isNotEmpty)
                              TextSpan(
                                text: "$speaker: ",
                                style: TextStyle(
                                  // Same colour the room uses for this
                                  // speaker, so a name learned in the thread
                                  // is recognised in the list.
                                  fontWeight: FontWeight.w700,
                                  color: speakerColor,
                                ),
                              ),
                            TextSpan(text: preview),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (room.unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: AppTheme.indigo,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    room.unread > 99 ? "99+" : "${room.unread}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that searches the directory and returns the chosen person.
class _UserSearchSheet extends StatefulWidget {
  final ChatService service;
  final String token;

  const _UserSearchSheet({required this.service, required this.token});

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  List<ChatUser> _results = const [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounce so a fast typist does not fire a request per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.service
          .searchUsers(token: widget.token, query: query.trim());
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLarge),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: localizations.chatFindPeople,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primarySoft,
                        foregroundImage: resolveMediaUrl(user.avatarUrl).isEmpty
                            ? null
                            : NetworkImage(resolveMediaUrl(user.avatarUrl)),
                        child: Text(
                          user.displayName.isEmpty
                              ? "?"
                              : user.displayName[0].toUpperCase(),
                          style: const TextStyle(color: AppTheme.primary),
                        ),
                      ),
                      title: Text(user.displayName),
                      subtitle: Text("@${user.username}"),
                      onTap: () => Navigator.of(context).pop(user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
