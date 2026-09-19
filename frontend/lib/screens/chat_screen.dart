import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/chat_service.dart";
import "../utils/theme.dart";
import "../widgets/state_views.dart";
import "chat_room_screen.dart";

/// The Trip Chat landing surface: the shared community room plus every direct
/// conversation and group the traveller belongs to.
class ChatScreen extends StatefulWidget {
  /// When false the screen renders bare, for embedding inside the home shell.
  final bool showScaffold;

  const ChatScreen({super.key, this.showScaffold = true});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _service = ChatService();

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
    final subtitle = last == null
        ? room.description
        : last.deleted
            ? localizations.chatDeleted
            : "${last.mine ? "You" : last.displayName}: ${last.text}";

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
              CircleAvatar(
                radius: 24,
                backgroundColor: room.type == ChatRoomType.community
                    ? AppTheme.primarySoft
                    : AppTheme.indigoSoft,
                foregroundImage: room.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(room.avatarUrl),
                child: Icon(
                  _icon,
                  color: room.type == ChatRoomType.community
                      ? AppTheme.primary
                      : AppTheme.indigo,
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
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
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
                        foregroundImage: user.avatarUrl.isEmpty
                            ? null
                            : NetworkImage(user.avatarUrl),
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
