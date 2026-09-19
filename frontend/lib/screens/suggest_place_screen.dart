import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/chat.dart";
import "../providers/auth_provider.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";

/// Lets a traveller nominate a place the catalogue is missing, and shows what
/// they have already sent in.
class SuggestPlaceScreen extends StatefulWidget {
  const SuggestPlaceScreen({super.key});

  @override
  State<SuggestPlaceScreen> createState() => _SuggestPlaceScreenState();
}

class _SuggestPlaceScreenState extends State<SuggestPlaceScreen> {
  final SocialService _service = SocialService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();

  List<Submission> _submissions = const [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadSubmissions() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final submissions = await _service.fetchMySubmissions(token);
      if (mounted) setState(() => _submissions = submissions);
    } catch (_) {
      // The list is supplementary; failing to load it must not block the form.
    }
  }

  Future<void> _submit() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final localizations = AppLocalizations.of(context);
    try {
      await _service.submitDestination(
        token: token,
        name: _name.text.trim(),
        category: _category.text.trim(),
        description: _description.text.trim(),
      );
      if (!mounted) return;
      _name.clear();
      _category.clear();
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.suggestPlaceThanks)),
      );
      await _loadSubmissions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.suggestPlaceTitle),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              localizations.suggestPlaceSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: localizations.suggestPlaceName,
              ),
              validator: (value) => (value ?? "").trim().isEmpty
                  ? localizations.suggestPlaceName
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _category,
              decoration: InputDecoration(
                labelText: localizations.suggestPlaceCategory,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: localizations.suggestPlaceDescription,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(localizations.suggestPlaceSubmit),
            ),
            if (_submissions.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                localizations.mySubmissions,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              for (final submission in _submissions)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          submission.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          localizations.statusPending,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
