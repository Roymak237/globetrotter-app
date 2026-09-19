import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";
import "../widgets/state_views.dart";

/// The notification inbox: replies to your comments, direct messages and
/// group invitations.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SocialService _service = SocialService();

  List<AppNotification> _items = const [];
  bool _loading = true;
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
      setState(() {
        _items = [
          for (final n in _items)
            AppNotification(
              id: n.id,
              type: n.type,
              actor: n.actor,
              text: n.text,
              createdAt: n.createdAt,
              read: true,
              destinationId: n.destinationId,
              roomId: n.roomId,
            ),
        ];
      });
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hasUnread = _items.any((n) => !n.read);

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
          return Container(
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
              ],
            ),
          );
        },
      ),
    );
  }
}
