import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../models/itinerary.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "../utils/destination_cost.dart";
import "../utils/theme.dart";
import "../widgets/itinerary_route_map.dart";
import "../widgets/state_views.dart";

class CreateItineraryScreen extends StatefulWidget {
  const CreateItineraryScreen({super.key});

  @override
  State<CreateItineraryScreen> createState() => _CreateItineraryScreenState();
}

class _CreateItineraryScreenState extends State<CreateItineraryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _notesController = TextEditingController();

  final List<String> _selectedDestinations = [];
  List<Destination> _allDestinations = [];
  DateTime? _startDate;
  DateTime? _endDate;
  Itinerary? _editingItinerary;
  bool _routeInitialized = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEditing => _editingItinerary != null;

  int? get _tripDays {
    if (_startDate == null || _endDate == null) return null;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  double get _estimatedDailyCost => _selectedDestinations.fold(
        0,
        (total, name) {
          final destination = _destinationForName(name);
          return total +
              (destination?.hasCostEstimate == true
                  ? destination!.avgCostPerDay
                  : 0);
        },
      );

  bool get _hasUnknownCosts => _selectedDestinations
      .any((name) => _destinationForName(name)?.hasCostEstimate != true);

  double get _estimatedTotalCost => _estimatedDailyCost * (_tripDays ?? 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeInitialized) return;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Itinerary) {
      _editingItinerary = arguments;
      _titleController.text = arguments.title;
      _startDate = DateTime.tryParse(arguments.startDate);
      _endDate = DateTime.tryParse(arguments.endDate);
      _startDateController.text = arguments.startDate;
      _endDateController.text = arguments.endDate;
      _notesController.text = arguments.notes;
      _selectedDestinations.addAll(arguments.destinations);
    }

    _routeInitialized = true;
    _loadDestinations();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ApiService().searchDestinations();
      if (!mounted) return;
      setState(() {
        _allDestinations = results;
        _selectedDestinations.removeWhere(
          (name) =>
              !_allDestinations.any((destination) => destination.name == name),
        );
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst("Exception: ", "");
        });
      }
    }
  }

  Destination? _destinationForName(String name) {
    for (final destination in _allDestinations) {
      if (destination.name == name) return destination;
    }
    return null;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");
    return "${date.year}-$month-$day";
  }

  Future<void> _pickStartDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: "Choose the first day",
      cancelText: "Not yet",
      confirmText: "Use date",
    );
    if (picked == null || !mounted) return;

    setState(() {
      _error = null;
      _startDate = DateUtils.dateOnly(picked);
      _startDateController.text = _formatDate(_startDate!);
      if (_endDate != null && _endDate!.isBefore(_startDate!)) {
        _endDate = _startDate;
        _endDateController.text = _formatDate(_endDate!);
      }
    });
  }

  Future<void> _pickEndDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final earliest = _startDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? earliest,
      firstDate: earliest,
      lastDate: DateTime(2100),
      helpText: "Choose the last day",
      cancelText: "Not yet",
      confirmText: "Use date",
    );
    if (picked == null || !mounted) return;

    setState(() {
      _error = null;
      _endDate = DateUtils.dateOnly(picked);
      _endDateController.text = _formatDate(_endDate!);
    });
  }

  void _toggleDestination(String name, bool selected) {
    setState(() {
      _error = null;
      if (selected && !_selectedDestinations.contains(name)) {
        _selectedDestinations.add(name);
      } else if (!selected) {
        _selectedDestinations.remove(name);
      }
    });
  }

  Future<void> _saveItinerary() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDestinations.isEmpty) {
      setState(
          () => _error = "Choose at least one destination for your route.");
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      final auth = context.read<AuthProvider>();
      if (_isEditing) {
        await auth.updateItinerary(
          itineraryId: _editingItinerary!.id,
          title: _titleController.text.trim(),
          destinations: _selectedDestinations,
          startDate: _startDateController.text,
          endDate: _endDateController.text,
          notes: _notesController.text.trim(),
        );
      } else {
        await auth.createItinerary(
          title: _titleController.text.trim(),
          destinations: _selectedDestinations,
          startDate: _startDateController.text,
          endDate: _endDateController.text,
          notes: _notesController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _costLabel(double value) {
    return "${(value / 1000).round()}k XAF";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: AppTheme.appBarBackground,
        title: Text(_isEditing ? "Edit trip" : "Plan a new trip"),
      ),
      body: _loading
          ? const AppLoadingView(message: "Opening the destination guide…")
          : _error != null && _allDestinations.isEmpty
              ? ErrorStateView(
                  title: "The guide is out of reach.",
                  message: _error!,
                  onRetry: _loadDestinations,
                )
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isEditing
                              ? "Give the journey a sharper shape."
                              : "Give the journey a shape.",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Set the dates, arrange your stops, and leave yourself a few useful notes.",
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                    height: 1.35,
                                  ),
                        ),
                        const SizedBox(height: 22),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    AppTheme.secondary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFF8A1721),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _titleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Trip title",
                            hintText: "Weekend on the coast",
                            prefixIcon: Icon(Icons.bookmark_outline_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? "Give your trip a title"
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _startDateController,
                                readOnly: true,
                                onTap: _pickStartDate,
                                decoration: const InputDecoration(
                                  labelText: "Start date",
                                  hintText: "Choose a date",
                                  prefixIcon: Icon(Icons.today_outlined),
                                  suffixIcon:
                                      Icon(Icons.calendar_month_outlined),
                                ),
                                validator: (_) => _startDate == null
                                    ? "Choose a start date"
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _endDateController,
                                readOnly: true,
                                onTap: _pickEndDate,
                                decoration: const InputDecoration(
                                  labelText: "End date",
                                  hintText: "Choose a date",
                                  prefixIcon:
                                      Icon(Icons.event_available_outlined),
                                  suffixIcon:
                                      Icon(Icons.calendar_month_outlined),
                                ),
                                validator: (_) {
                                  if (_endDate == null) {
                                    return "Choose an end date";
                                  }
                                  if (_startDate != null &&
                                      _endDate!.isBefore(_startDate!)) {
                                    return "Must follow start";
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            labelText: "Notes",
                            hintText: "Anything you want to remember…",
                            prefixIcon: Icon(Icons.sticky_note_2_outlined),
                            alignLabelWithHint: true,
                            helperText:
                                "Keep packing lists, ideas, or reminders here",
                          ),
                        ),
                        const SizedBox(height: 26),
                        const _SectionHeading(
                          icon: Icons.route_rounded,
                          title: "Choose your stops",
                          subtitle:
                              "Select places, then drag the route below into the order you want to travel it.",
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allDestinations.map((destination) {
                            final selected = _selectedDestinations.contains(
                              destination.name,
                            );
                            return FilterChip(
                              label: Text(
                                  "${destination.name} • ${destinationCostLabel(context, destination, perDay: true)}"),
                              selected: selected,
                              avatar: Icon(
                                selected
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                size: 16,
                              ),
                              onSelected: (value) => _toggleDestination(
                                destination.name,
                                value,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _RouteOrderCard(
                          destinations: _selectedDestinations,
                          destinationForName: _destinationForName,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final destination =
                                  _selectedDestinations.removeAt(oldIndex);
                              _selectedDestinations.insert(
                                  newIndex, destination);
                            });
                          },
                          onRemove: (name) => _toggleDestination(name, false),
                        ),
                        if (_selectedDestinations.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          ItineraryRouteMap(
                            destinationNames: _selectedDestinations,
                            destinations: _allDestinations,
                          ),
                        ],
                        const SizedBox(height: 14),
                        _CostSummaryCard(
                          days: _tripDays,
                          stopCount: _selectedDestinations.length,
                          dailyCost: _estimatedDailyCost,
                          totalCost: _estimatedTotalCost,
                          hasUnknownCosts: _hasUnknownCosts,
                          costLabel: _costLabel,
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _saveItinerary,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(_isEditing
                                  ? Icons.check_rounded
                                  : Icons.save_outlined),
                          label: Text(_saving
                              ? "Saving your route…"
                              : _isEditing
                                  ? "Save changes"
                                  : "Save itinerary"),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: AppTheme.displayFontFamily,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteOrderCard extends StatelessWidget {
  final List<String> destinations;
  final Destination? Function(String name) destinationForName;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;

  const _RouteOrderCard({
    required this.destinations,
    required this.destinationForName,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: destinations.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_outlined,
                      color: AppTheme.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Your route will appear here as you choose stops.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 5),
                  child: Text(
                    "YOUR ROUTE / ${destinations.length} STOP${destinations.length == 1 ? "" : "S"}",
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.secondary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: destinations.length,
                  onReorder: onReorder,
                  itemBuilder: (context, index) {
                    final name = destinations[index];
                    final destination = destinationForName(name);
                    return ListTile(
                      key: ValueKey(name),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                      leading: _RouteNumber(number: index + 1),
                      title: Text(
                        name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontFamily: AppTheme.displayFontFamily,
                                ),
                      ),
                      subtitle: destination == null
                          ? null
                          : Text(
                              "${destination.region}  •  ${destinationCostLabel(context, destination, perDay: true)}",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: "Remove $name",
                            onPressed: () => onRemove(name),
                            icon: const Icon(Icons.close_rounded, size: 19),
                            color: AppTheme.textSecondary,
                          ),
                          ReorderableDelayedDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _RouteNumber extends StatelessWidget {
  final int number;

  const _RouteNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        "$number",
        style: const TextStyle(
          color: AppTheme.primaryDark,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CostSummaryCard extends StatelessWidget {
  final int? days;
  final int stopCount;
  final double dailyCost;
  final double totalCost;
  final bool hasUnknownCosts;
  final String Function(double value) costLabel;

  const _CostSummaryCard({
    required this.days,
    required this.stopCount,
    required this.dailyCost,
    required this.totalCost,
    required this.hasUnknownCosts,
    required this.costLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasEstimate = days != null && stopCount > 0;
    final isFrench = AppLocalizations.of(context).locale.languageCode == "fr";
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, color: AppTheme.primaryDark),
              const SizedBox(width: 8),
              Text(
                "TRIP ESTIMATE",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (!hasEstimate)
            Text(
              stopCount == 0
                  ? "Choose stops and dates to see a rough daily estimate."
                  : "Add both dates to see your rough trip estimate.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _EstimateMetric(
                    label: "DAYS",
                    value: "$days",
                  ),
                ),
                Expanded(
                  child: _EstimateMetric(
                    label: "PER DAY",
                    value: costLabel(dailyCost),
                  ),
                ),
                Expanded(
                  child: _EstimateMetric(
                    label: hasUnknownCosts
                        ? (isFrench ? "SOUS-TOTAL" : "SUBTOTAL")
                        : "TOTAL",
                    value: costLabel(totalCost),
                    emphasize: true,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (hasUnknownCosts) ...[
            Text(
              isFrench
                  ? "Sous-total hors estimations inconnues : le coût de certains arrêts n’est pas disponible."
                  : "Subtotal excludes unknown estimates: costs for some stops are not available.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            "Estimate uses average destination costs and is meant for planning only.",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _EstimateMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _EstimateMetric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: emphasize ? AppTheme.primaryDark : AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
