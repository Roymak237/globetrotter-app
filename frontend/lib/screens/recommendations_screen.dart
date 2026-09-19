import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "../utils/preferences.dart";
import "../utils/theme.dart";
import "../widgets/destination_card.dart";
import "../widgets/preference_editor_dialog.dart";
import "../widgets/state_views.dart";

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _api = ApiService();
  List<Destination> _recommendations = [];
  bool _loading = true;
  bool _syncingProfile = false;
  String? _preferenceSignature;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    auth.addListener(_handleAuthChanged);
    _loadRecommendations();
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (_syncingProfile) return;
    final preferences =
        context.read<AuthProvider>().currentUser?.preferences ?? <String>[];
    final signature = preferences.join("|");
    if (_preferenceSignature == null) {
      _preferenceSignature = signature;
      return;
    }
    if (signature == _preferenceSignature) return;
    _preferenceSignature = signature;
    if (mounted) _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      _syncingProfile = true;
      try {
        await auth.fetchProfile();
      } catch (_) {
        // Recommendations can still load if the profile refresh is unavailable.
      } finally {
        _syncingProfile = false;
      }
      _preferenceSignature =
          (auth.currentUser?.preferences ?? <String>[]).join("|");

      final token = auth.token;
      if (token == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = "Please sign in to see recommendations.";
          });
        }
        return;
      }

      final results = await _api.fetchRecommendations(token: token);
      if (mounted) {
        setState(() {
          _recommendations = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst("Exception: ", "");
        });
      }
    }
  }

  Future<void> _editPreferences() async {
    final localizations = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final changed = await showPreferenceEditor(
      context,
      initialPreferences: user.preferences.toSet(),
      onSave: (preferences) async {
        _syncingProfile = true;
        try {
          await auth.updatePreferences(preferences: preferences);
        } finally {
          _syncingProfile = false;
        }
      },
    );
    if (!mounted || !changed) return;

    await _loadRecommendations();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.recommendationsRefreshed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final preferences =
        context.watch<AuthProvider>().currentUser?.preferences ?? <String>[];

    if (_loading) {
      return AppLoadingView(message: localizations.recommendationsLoading);
    }

    if (_error != null) {
      return ErrorStateView(
        title: localizations.recommendationsErrorTitle,
        message: _error!,
        onRetry: _loadRecommendations,
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadRecommendations,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          _RecommendationsHeader(
            preferences: preferences,
            onEdit: _editPreferences,
          ),
          if (_recommendations.isEmpty)
            EmptyStateView(
              icon: Icons.auto_awesome_outlined,
              title: localizations.journeyAwaits,
              message: localizations.recommendationsEmptyMessage,
              action: OutlinedButton.icon(
                onPressed: _editPreferences,
                icon: const Icon(Icons.tune_rounded),
                label: Text(localizations.tunePreferences),
              ),
            )
          else
            ..._recommendations.map(
              (destination) => DestinationCard(
                destination: destination,
                onTap: () => Navigator.pushNamed(
                  context,
                  "/destination_detail",
                  arguments: destination,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationsHeader extends StatelessWidget {
  final List<String> preferences;
  final VoidCallback onEdit;

  const _RecommendationsHeader({
    required this.preferences,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.recommendationsHeading,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preferences.isEmpty
                          ? localizations.recommendationsLoading
                          : localizations.recommendationsSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(localizations.editPreferences),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (preferences.isEmpty)
            Text(
              localizations.recommendationsNoSignals,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: preferences
                  .map(
                    (preference) => Chip(
                      label: Text(preferenceLabel(preference)),
                      avatar: const Icon(Icons.check_rounded, size: 15),
                      backgroundColor: AppTheme.primarySoft,
                      side: BorderSide.none,
                      labelStyle: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
