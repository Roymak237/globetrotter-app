import 'package:flutter/material.dart';

Future<String?> chatPrompt(BuildContext context, String title,
        {String initial = '',
        int maxLength = 200,
        String hint = '',
        bool allowEmpty = false}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _ChatPrompt(
            title: title,
            initial: initial,
            maxLength: maxLength,
            hint: hint,
            allowEmpty: allowEmpty));

Future<bool> chatConfirm(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm')),
              ],
            )) ??
    false;

class _ChatPrompt extends StatefulWidget {
  final String title, initial, hint;
  final int maxLength;
  final bool allowEmpty;
  const _ChatPrompt(
      {required this.title,
      required this.initial,
      required this.maxLength,
      required this.hint,
      required this.allowEmpty});
  @override
  State<_ChatPrompt> createState() => _ChatPromptState();
}

class _ChatPromptState extends State<_ChatPrompt> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.maxLength,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: widget.hint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: !widget.allowEmpty && _controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, _controller.text.trim()),
              child: const Text('Save'))
        ],
      );
}
