import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/itinerary.dart";
import "../providers/auth_provider.dart";
import "../utils/theme.dart";
import "../widgets/itinerary_card.dart";
import "../widgets/share_itinerary_dialog.dart";
import "../widgets/state_views.dart";

class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen> {
  List<Itinerary> _itineraries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItineraries();
  }

  Future<void> _loadItineraries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AuthProvider>().fetchItineraries();
      if (mounted) {
        setState(() {
          _itineraries = list;
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.itineraryHeading,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localizations.itinerarySubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                tooltip: "Create a new itinerary",
                onPressed: () async {
                  await Navigator.pushNamed(context, "/create_itinerary");
                  _loadItineraries();
                },
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? AppLoadingView(message: localizations.itineraryLoading)
              : _error != null
                  ? ErrorStateView(
                      title: localizations.itineraryErrorTitle,
                      message: _error!,
                      onRetry: _loadItineraries,
                    )
                  : _itineraries.isEmpty
                      ? EmptyStateView(
                          icon: Icons.map_outlined,
                          title: localizations.itineraryEmptyTitle,
                          message: localizations.itineraryEmptyMessage,
                          action: ElevatedButton.icon(
                            onPressed: () async {
                              await Navigator.pushNamed(
                                  context, "/create_itinerary");
                              _loadItineraries();
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text(localizations.planNewTrip),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppTheme.primary,
                          onRefresh: _loadItineraries,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 2, bottom: 24),
                            itemCount: _itineraries.length,
                            itemBuilder: (context, index) {
                              final itinerary = _itineraries[index];
                              return ItineraryCard(
                                itinerary: itinerary,
                                onTap: () async {
                                  final changed = await Navigator.pushNamed(
                                    context,
                                    "/itinerary_detail",
                                    arguments: itinerary,
                                  );
                                  if (mounted && changed == true) {
                                    _loadItineraries();
                                  }
                                },
                                onShare: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final username =
                                      await showShareItineraryDialog(
                                    context,
                                    itineraryId: itinerary.id,
                                  );
                                  if (!mounted || username == null) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                        content: Text("Shared with $username")),
                                  );
                                },
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
