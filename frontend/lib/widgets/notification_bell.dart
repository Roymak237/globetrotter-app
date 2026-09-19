import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../providers/auth_provider.dart";
import "../screens/notifications_screen.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";

/// App-bar bell that surfaces the unread notification count.
///
/// Polls on a slow timer rather than holding a connection, matching how the
/// rest of the app talks to the backend.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final SocialService _service = SocialService();
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final result = await _service.fetchNotifications(token);
      if (mounted) setState(() => _unread = result.unread);
    } catch (_) {
      // A missed poll is harmless; the next tick tries again.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().isAuthenticated) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _open,
          icon: const Icon(Icons.notifications_none_rounded),
          color: AppTheme.textPrimary,
          tooltip: "Notifications",
        ),
        if (_unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.background, width: 1.5),
              ),
              child: Text(
                _unread > 9 ? "9+" : "$_unread",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
