import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../utils/theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  final String token;
  const BlockedUsersScreen({super.key, required this.token});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _service = ChatService();
  List<ChatUser> _users = [];
  bool _loading = true;
  final Set<String> _busy = {};
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await _service.blockedUsers(widget.token);
      if (mounted)
        setState(() {
          _users = users;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(ChatUser user) async {
    setState(() => _busy.add(user.username));
    try {
      await _service.unblock(widget.token, user.username);
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy.remove(user.username));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Blocked people'),
            flexibleSpace: AppTheme.appBarBackground,
            foregroundColor: Colors.white),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ...[
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry'))
                    ] else if (_users.isEmpty)
                      const ListTile(title: Text('No blocked people')),
                    for (final user in _users)
                      ListTile(
                          title: Text(user.displayName),
                          subtitle: Text('@${user.username}'),
                          trailing: TextButton(
                              onPressed: _busy.contains(user.username)
                                  ? null
                                  : () => _unblock(user),
                              child: const Text('Unblock'))),
                  ],
                ),
              ),
      );
}
