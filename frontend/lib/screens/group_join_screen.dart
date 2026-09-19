import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../utils/theme.dart';
import '../widgets/chat_dialogs.dart';

/// Returns a joined or newly created room to the chat landing screen.
class GroupJoinScreen extends StatefulWidget {
  final String token;
  const GroupJoinScreen({super.key, required this.token});
  @override
  State<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends State<GroupJoinScreen> {
  final _service = ChatService();
  final _query = TextEditingController();
  final _code = TextEditingController();
  List<ChatRoom> _groups = [];
  bool _loading = true, _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups =
          await _service.discoverGroups(widget.token, _query.text.trim());
      if (mounted && generation == _generation)
        setState(() => _groups = groups);
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await chatPrompt(context, 'Create a travel group',
        maxLength: 80, hint: 'Group name');
    if (!mounted || name == null) return;
    final description = await chatPrompt(context, 'Group description',
        maxLength: 300, allowEmpty: true);
    if (!mounted || description == null) return;
    await _act(() async {
      final room = await _service.createGroup(
          token: widget.token, name: name, description: description);
      if (mounted) Navigator.pop(context, room);
    });
  }

  Future<void> _request(ChatRoom group) async {
    final message = await chatPrompt(context, 'Ask to join ${group.name}',
        hint: 'Introduce yourself (optional)', allowEmpty: true);
    if (!mounted || message == null) return;
    await _act(() async {
      await _service.requestJoin(widget.token, group.id, message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent to the group admins.')));
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Travel groups'),
            flexibleSpace: AppTheme.appBarBackground,
            foregroundColor: Colors.white),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.group_add),
                    label: const Text('Create a group')),
                const SizedBox(height: 20),
                Text('Have an invite code?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                    controller: _code,
                    maxLength: 8,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Invite code')),
                OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _act(() async {
                              if (_code.text.trim().isEmpty)
                                throw Exception('Enter an invite code.');
                              final room = await _service.joinByCode(
                                  widget.token, _code.text);
                              if (mounted) Navigator.pop(context, room);
                            }),
                    child: const Text('Join with code')),
                const Divider(height: 32),
                Text('Discover groups',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                        hintText: 'Search groups',
                        suffixIcon: IconButton(
                            onPressed: _load, icon: const Icon(Icons.search)))),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))
                else if (_error != null) ...[
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry'))
                ] else if (_groups.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No groups found.'))
                else
                  for (final group in _groups)
                    Card(
                        child: ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: AppTheme.primarySoft,
                          child: Icon(Icons.groups, color: AppTheme.primary)),
                      title: Text(group.name),
                      subtitle: Text(
                          '${group.description}\n${group.memberCount} members'),
                      isThreeLine: true,
                      trailing: TextButton(
                          onPressed: _busy || group.requested
                              ? null
                              : () => _request(group),
                          child: Text(group.requested ? 'Pending' : 'Request')),
                    )),
              ],
            )),
      );
}
