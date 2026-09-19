import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../providers/auth_provider.dart";
import "../services/social_service.dart";
import "../utils/theme.dart";

/// Lets the traveller choose the tags that steer their personalised feed.
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  static const int _maxInterests = 12;

  final SocialService _service = SocialService();
  final Set<String> _selected = {};

  List<String> _available = const [];
  bool _loading = true;
  bool _saving = false;
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
      final result = await _service.fetchInterests(token);
      if (!mounted) return;
      setState(() {
        _available = result.available;
        _selected
          ..clear()
          ..addAll(result.interests);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> _save() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _saving) return;

    setState(() => _saving = true);
    final localizations = AppLocalizations.of(context);
    try {
      await _service.saveInterests(token: token, interests: _selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.interestsSaved)),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else if (_selected.length < _maxInterests) {
        _selected.add(tag);
      } else {
        // Silently ignoring the tap would look broken, so explain the cap.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("You can pick up to $_maxInterests interests")),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.interestsTitle),
        flexibleSpace: AppTheme.appBarBackground,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      localizations.interestsSubtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in _available)
                          FilterChip(
                            label: Text(tag),
                            selected: _selected.contains(tag),
                            onSelected: (_) => _toggle(tag),
                            backgroundColor: AppTheme.surface,
                            selectedColor: AppTheme.primarySoft,
                            checkmarkColor: AppTheme.primary,
                            side: BorderSide(
                              color: _selected.contains(tag)
                                  ? AppTheme.primary
                                  : AppTheme.border,
                            ),
                            labelStyle: TextStyle(
                              color: _selected.contains(tag)
                                  ? AppTheme.primaryDark
                                  : AppTheme.textPrimary,
                              fontWeight: _selected.contains(tag)
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(localizations.interestsSave),
                    ),
                  ],
                ),
    );
  }
}
