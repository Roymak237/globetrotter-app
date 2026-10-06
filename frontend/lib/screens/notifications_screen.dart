import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "../services/chat_service.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";
import "../widgets/state_views.dart";
import "chat_room_screen.dart";

/// The notification inbox: replies to your comments, direct messages and
/// group invitations.
class NotificationsScreen extends StatefulWidget {
  /// Transport overrides, for tests only.
  ///
  /// None of these services take an injectable client, so this is the only
  /// seam through which the inbox can be exercised without a network.
  /// Production leaves all three null and gets the real services.
  @visibleForTesting
  final SocialService? social;
  @visibleForTesting
  final ChatService? chat;
  @visibleForTesting
  final ApiService? api;

  const NotificationsScreen({super.key, this.social, this.chat, this.api});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final SocialService _service = widget.social ?? SocialService();
  late final ChatService _chat = widget.chat ?? ChatService();
  late final ApiService _api = widget.api ?? ApiService();

  List<AppNotification> _items = const [];
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final result = await _service.fetchNotifications(token);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> _markAllRead() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      await _service.markNotificationsRead(token: token);
      if (!mounted) return;
      // Reflect the change locally rather than refetching the whole inbox.
      setState(() => _items = [for (final n in _items) _asRead(n)]);
    } catch (_) {
      // Leaving the badge in place is a safe failure here.
    }
  }

  IconData _iconFor(String type) => switch (type) {
        "reply" => Icons.reply_rounded,
        "message" => Icons.chat_bubble_rounded,
        "invite" => Icons.group_add_rounded,
        _ => Icons.notifications_rounded,
      };

  /// True when there is somewhere for a tap to go.
  ///
  /// Rows without a target stay inert rather than taking a tap and doing
  /// nothing, which reads as a broken button.
  bool _hasTarget(AppNotification item) =>
      (item.roomId?.isNotEmpty ?? false) ||
      (item.destinationId?.isNotEmpty ?? false);

  AppNotification _asRead(AppNotification n) => AppNotification(
        id: n.id,
        type: n.type,
        actor: n.actor,
        text: n.text,
        createdAt: n.createdAt,
        read: true,
        destinationId: n.destinationId,
        roomId: n.roomId,
      );

  /// Open whatever the notification is about.
  ///
  /// These rows used to be inert: the inbox could tell you that someone had
  /// written to you and then leave you to go and find the conversation
  /// yourself. The target was in the payload the whole time — `roomId` for a
  /// message or invitation, `destinationId` for a reply to a comment — and
  /// simply went unread by the screen displaying it.
  Future<void> _open(AppNotification item) async {
    if (_opening || !_hasTarget(item)) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() {
      _opening = true;
      // Opening it is the acknowledgement, so the row settles immediately.
      // The server is told too, but a failed write must not block the
      // navigation it was only meant to accompany.
      _items = [
        for (final n in _items) n.id == item.id ? _asRead(n) : n,
      ];
    });
    unawaited(_service.markNotificationsRead(
        token: token, ids: [item.id]).catchError((_) {}));

    try {
      final roomId = item.roomId;
      if (roomId != null && roomId.isNotEmpty) {
        final rooms = await _chat.fetchRooms(token);
        ChatRoom? room;
        for (final candidate in rooms) {
          if (candidate.id == roomId) {
            room = candidate;
            break;
          }
        }
        if (!mounted) return;
        if (room == null) throw Exception(_missingTargetMessage);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ChatRoomScreen(room: room!)),
        );
        // The thread was just read, so the unread counts behind it are stale.
        if (mounted) await _load();
        return;
      }

      final destinationId = item.destinationId!;
      final destination = await _api.getDestination(destinationId);
      if (!mounted) return;
      await Navigator.of(context)
          .pushNamed("/destination_detail", arguments: destination);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Set in [build] so the thrown message can be localized without reaching
  /// for a `BuildContext` from inside the async gap.
  String _missingTargetMessage = "";

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hasUnread = _items.any((n) => !n.read);
    _missingTargetMessage = localizations.notificationsOpenFailed;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.notificationsTitle),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                localizations.notificationsMarkAllRead,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
      body: _buildBody(localizations),
    );
  }

  Widget _buildBody(AppLocalizations localizations) {
    if (_loading) {
      return AppLoadingView(message: localizations.notificationsTitle);
    }
    if (_error != null) {
      return ErrorStateView(
        title: localizations.notificationsTitle,
        message: _error!,
        onRetry: _load,
      );
    }
    if (_items.isEmpty) {
      return EmptyStateView(
        icon: Icons.notifications_none_rounded,
        title: localizations.notificationsTitle,
        message: localizations.notificationsEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _items[index];
          final target = _hasTarget(item);
          final row = Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // Unread rows get the soft brand wash so they stand out without
              // needing a separate badge on every row.
              color: item.read ? AppTheme.surface : AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: item.read ? AppTheme.border : AppTheme.primary,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      item.read ? AppTheme.background : AppTheme.surface,
                  child: Icon(
                    _iconFor(item.type),
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              item.read ? FontWeight.w400 : FontWeight.w600,
                        ),
                  ),
                ),
                // A chevron is the only thing that tells someone a row leads
                // somewhere before they tap it.
                if (target)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary),
              ],
            ),
          );

          if (!target) return row;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _opening ? null : () => _open(item),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: row,
            ),
          );
        },
      ),
    );
  }
}
