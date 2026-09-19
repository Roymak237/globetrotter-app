import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../utils/theme.dart';
import '../widgets/chat_dialogs.dart';
import '../widgets/chat_media.dart';

/// Pops true after leaving; the room screen must then close as well.
class GroupInfoScreen extends StatefulWidget {
  final ChatRoom room;
  final String token;
  const GroupInfoScreen({super.key, required this.room, required this.token});
  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _service = ChatService();
  final _media = MediaService();
  late ChatRoom _room = widget.room;
  List<ChatUser> _members = [], _requests = [];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _media.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rooms = await _service.fetchRooms(widget.token);
      final current = rooms.where((r) => r.id == _room.id).firstOrNull;
      if (current == null)
        throw Exception('You are no longer a member of this group.');
      final members = await _service.groupMembers(widget.token, _room.id);
      final requests = current.isAdmin
          ? await _service.joinRequests(widget.token, _room.id)
          : <ChatUser>[];
      if (mounted)
        setState(() {
          _room = current;
          _members = members;
          _requests = requests;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final name = await chatPrompt(context, 'Group name',
        initial: _room.name, maxLength: 80);
    if (!mounted || name == null) return;
    final description = await chatPrompt(context, 'Description',
        initial: _room.description, maxLength: 300, allowEmpty: true);
    if (!mounted || description == null) return;
    await _act(() async {
      await _service.editGroup(widget.token, _room.id,
          name: name, description: description);
    });
  }

  Future<void> _memberAction(ChatUser person, String action) async {
    if (!await chatConfirm(
        context,
        '${action == 'remove' ? 'Remove' : action == 'promote' ? 'Promote' : 'Demote'} @${person.username}?',
        'This changes their access to the group.')) return;
    if (!mounted) return;
    await _act(() async {
      if (action == 'remove') {
        await _service.removeMember(widget.token, _room.id, person.username);
      } else {
        await _service.setAdmin(
            widget.token, _room.id, person.username, action == 'promote');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Group info'),
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
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null) ...[
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry'))
                    ],
                    if (_room.avatarUrl.startsWith('/api/media/'))
                      ChatAttachmentView(
                          token: widget.token,
                          attachment: ChatAttachment(
                              url: _room.avatarUrl, kind: 'image')),
                    Text(_room.name,
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(_room.description),
                    Text('${_members.length} members'),
                    if (_room.isAdmin) ...[
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: _busy ? null : _edit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit group')),
                        OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _act(() async {
                                      final photo = await _media.pickAndUpload(
                                          widget.token,
                                          imageOnly: true);
                                      if (!mounted || photo == null) return;
                                      await _service.editGroup(
                                          widget.token, _room.id,
                                          name: _room.name,
                                          description: _room.description,
                                          avatarUrl: photo.url);
                                    }),
                            icon: const Icon(Icons.photo_outlined),
                            label: const Text('Group photo')),
                      ]),
                      Card(
                          child: ListTile(
                        title: const Text('Invite code'),
                        subtitle:
                            SelectableText(_room.inviteCode ?? 'Unavailable'),
                        trailing: IconButton(
                            tooltip: 'Copy invite code',
                            icon: const Icon(Icons.copy),
                            onPressed: _room.inviteCode == null
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: _room.inviteCode!));
                                    if (context.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content:
                                                  Text('Invite code copied')));
                                  }),
                      )),
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (!await chatConfirm(
                                      context,
                                      'Rotate invite code?',
                                      'The old code will stop working.'))
                                    return;
                                  if (!mounted) return;
                                  await _act(() async {
                                    await _service.rotateInvite(
                                        widget.token, _room.id);
                                  });
                                },
                          child: const Text('Rotate invite code')),
                      Text('Join requests (${_requests.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      for (final person in _requests)
                        Card(
                            child: Column(children: [
                          ListTile(
                              title: Text(person.displayName),
                              subtitle: Text(
                                  '@${person.username}\n${person.message}')),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(() async {
                                              await _service.reviewRequest(
                                                  widget.token,
                                                  _room.id,
                                                  person.username,
                                                  false);
                                            }),
                                    child: const Text('Decline')),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(() async {
                                              await _service.reviewRequest(
                                                  widget.token,
                                                  _room.id,
                                                  person.username,
                                                  true);
                                            }),
                                    child: const Text('Approve')),
                              ]),
                        ])),
                      OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final username = await chatPrompt(
                                      context, 'Add member',
                                      hint: 'Exact username', maxLength: 80);
                                  if (!mounted || username == null) return;
                                  await _act(() async {
                                    await _service.addMember(
                                        widget.token, _room.id, username);
                                  });
                                },
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Add member')),
                    ],
                    const Divider(),
                    for (final person in _members)
                      ListTile(
                        title: Text(person.displayName),
                        subtitle: Text('@${person.username}'
                            '${person.isCreator ? ' · Creator' : person.isAdmin ? ' · Admin' : ''}'),
                        trailing: !_room.isAdmin || person.isCreator || _busy
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (action) =>
                                    _memberAction(person, action),
                                itemBuilder: (_) => [
                                      PopupMenuItem(
                                          value: person.isAdmin
                                              ? 'demote'
                                              : 'promote',
                                          child: Text(person.isAdmin
                                              ? 'Remove admin role'
                                              : 'Make admin')),
                                      const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove member')),
                                    ]),
                      ),
                    const Divider(),
                    TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (!await chatConfirm(context, 'Leave group?',
                                    'You will need an invite or approval to rejoin.'))
                                  return;
                                if (!mounted) return;
                                await _act(() async {
                                  await _service.leaveGroup(
                                      token: widget.token, roomId: _room.id);
                                  if (mounted) Navigator.pop(context, true);
                                });
                              },
                        icon: const Icon(Icons.exit_to_app,
                            color: AppTheme.error),
                        label: const Text('Leave group',
                            style: TextStyle(color: AppTheme.error))),
                  ],
                ),
              ),
      );
}
