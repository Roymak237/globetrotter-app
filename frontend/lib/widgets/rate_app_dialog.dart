import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../providers/auth_provider.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";

/// Star rating and optional written feedback about the app itself.
class RateAppDialog extends StatefulWidget {
  const RateAppDialog({super.key});

  /// Convenience opener so callers do not repeat the boilerplate.
  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => const RateAppDialog(),
      );

  @override
  State<RateAppDialog> createState() => _RateAppDialogState();
}

class _RateAppDialogState extends State<RateAppDialog> {
  final SocialService _service = SocialService();
  final TextEditingController _feedback = TextEditingController();

  int _stars = 0;
  bool _saving = false;
  double _average = 0;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final token = context.read<AuthProvider>().token;
    try {
      final summary = await _service.fetchAppReviews(token: token);
      if (!mounted) return;
      setState(() {
        _average = summary.average;
        _count = summary.count;
        // Pre-fill so re-rating edits the existing entry rather than starting blank.
        if (summary.mine != null) {
          _stars = summary.mine!.stars;
          _feedback.text = summary.mine!.feedback ?? "";
        }
      });
    } catch (_) {
      // Showing the dialog without the aggregate is perfectly usable.
    }
  }

  Future<void> _submit() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _stars == 0 || _saving) return;

    setState(() => _saving = true);
    final localizations = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.submitAppReview(
        token: token,
        stars: _stars,
        feedback: _feedback.text.trim(),
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.rateAppThanks)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      title: Text(localizations.rateAppTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.rateAppPrompt,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          if (_count > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 16, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text(
                  "${_average.toStringAsFixed(1)} · $_count",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  onPressed: () => setState(() => _stars = star),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    star <= _stars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppTheme.accent,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _feedback,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: "Optional feedback"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _stars == 0 || _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(localizations.rateAppSubmit),
        ),
      ],
    );
  }
}
