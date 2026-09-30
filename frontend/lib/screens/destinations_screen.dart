import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../services/api_service.dart";
import "../utils/destination_cost.dart";
import "../utils/layout.dart";
import "../utils/theme.dart";
import "../widgets/destination_card.dart";
import "../widgets/state_views.dart";

class DestinationsScreen extends StatefulWidget {
  const DestinationsScreen({super.key});

  @override
  State<DestinationsScreen> createState() => _DestinationsScreenState();
}

class _DestinationsScreenState extends State<DestinationsScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();
  List<Destination> _destinations = [];
  bool _loading = true;
  String? _error;
  String? _selectedType;
  String? _selectedRegion;
  int? _maxCost;
  String _sortMode = "recommended";

  static const _typeFilters = [
    {"label": "All", "tag": ""},
    {"label": "Gaming", "tag": "gaming"},
    {"label": "Dining", "tag": "dining"},
    {"label": "Tourist", "tag": "tourist"},
    {"label": "Leisure", "tag": "leisure"},
    {"label": "Recreation", "tag": "recreation"},
    {"label": "Shopping", "tag": "shopping"},
    {"label": "Schools", "tag": "education"},
    {"label": "Beach", "tag": "relaxation"},
    {"label": "Hiking", "tag": "hiking"},
    {"label": "Landmarks", "tag": "landmark"},
    {"label": "Family", "tag": "family"},
  ];

  static const _regions = [
    "Adamawa",
    "Centre",
    "East",
    "Far North",
    "Littoral",
    "North",
    "Northwest",
    "South",
    "Southwest",
    "West",
  ];

  @override
  void initState() {
    super.initState();
    _loadDestinations();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _api.searchDestinations(
        query: _controller.text.trim(),
        tag: _selectedType,
        region: _selectedRegion,
        maxCost: _maxCost,
      );
      if (mounted) {
        setState(() {
          _destinations = _sortResults(results);
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

  List<Destination> _sortResults(List<Destination> destinations) {
    final sorted = [...destinations];
    switch (_sortMode) {
      case "cost_low":
        sorted.sort((a, b) => compareDestinationCosts(a, b));
        break;
      case "cost_high":
        sorted.sort((a, b) => compareDestinationCosts(a, b, descending: true));
        break;
      case "name":
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
    }
    return sorted;
  }

  String get _sortLabel {
    switch (_sortMode) {
      case "cost_low":
        return "Lowest cost";
      case "cost_high":
        return "Highest cost";
      case "name":
        return "A–Z";
      default:
        return "Recommended";
    }
  }

  /// The effective text scale, clamped.
  ///
  /// A sliver header has to state its height up front, so the filter bar
  /// cannot simply size itself to its contents. Deriving the height from the
  /// text scale keeps the chips from being clipped for anyone browsing at a
  /// larger accessibility font size.
  double _barScale(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: _loadDestinations,
      color: AppTheme.primary,
      child: CustomScrollView(
        // Keeps pull-to-refresh reachable even when the results are too few to
        // fill the screen.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildIntro(context, localizations)),
          SliverPersistentHeader(
            // Floating rather than pinned. Scrolling down clears the filters
            // away so the photographs get the full screen, and the smallest
            // upward swipe brings them straight back — so changing a filter
            // never means scrolling to the top of 57 results first.
            floating: true,
            delegate: _FilterBarDelegate(
              extent: 96 * _barScale(context),
              builder: (context, overlapsContent) =>
                  _buildFilterBar(context, localizations, overlapsContent),
            ),
          ),
          _buildResults(context, localizations),
        ],
      ),
    );
  }

  /// The title, shortcuts and search field. Scrolls away with the list.
  Widget _buildIntro(BuildContext context, AppLocalizations localizations) {
    final hasAdvancedFilters = _selectedRegion != null || _maxCost != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.destinationsHeading,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localizations.destinationsSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: localizations.mapShortcut,
                    onPressed: () => Navigator.pushNamed(context, "/map"),
                    icon: const Icon(Icons.map_outlined),
                    color: AppTheme.primary,
                  ),
                  IconButton(
                    tooltip: localizations.savedShortcut,
                    onPressed: () => Navigator.pushNamed(context, "/saved"),
                    icon: const Icon(Icons.favorite_border_rounded),
                    color: AppTheme.secondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadDestinations(),
            decoration: InputDecoration(
              hintText: localizations.searchPlacesHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: localizations.filterTooltip,
                icon: Icon(
                  hasAdvancedFilters
                      ? Icons.filter_alt_rounded
                      : Icons.tune_rounded,
                ),
                onPressed: _showFilterSheet,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The activity chips, result count and sort control.
  Widget _buildFilterBar(
    BuildContext context,
    AppLocalizations localizations,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // Transparent while it sits in the normal flow, so the backdrop still
        // shows through exactly as before. Once it floats over the cards it
        // has to be opaque, or photographs slide past underneath the chips.
        color: overlapsContent ? AppTheme.background : Colors.transparent,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44 * _barScale(context),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: _typeFilters.map((filter) {
                final tag = filter["tag"] as String;
                final isSelected = (_selectedType ?? "") == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(tag == "education" &&
                            localizations.locale.languageCode == "fr"
                        ? "Écoles"
                        : filter["label"] as String),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedType = tag.isEmpty || isSelected ? null : tag;
                      });
                      _loadDestinations();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Expanded rather than a fixed height: the bar's total extent is
          // already decided, so this absorbs whatever is left instead of
          // overflowing it.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _loading
                          ? localizations.placesReading
                          : localizations.placesFound(_destinations.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showSortSheet,
                    icon: const Icon(Icons.swap_vert_rounded, size: 18),
                    label: Text(_sortLabel),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    if (_loading) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppLoadingView(message: localizations.placesReading),
      );
    }
    if (_error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorStateView(
          title: localizations.destinationsErrorTitle,
          message: _error!,
          onRetry: _loadDestinations,
        ),
      );
    }
    if (_destinations.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateView(
          icon: Icons.explore_off_rounded,
          title: localizations.destinationsEmptyTitle,
          message: localizations.destinationsEmptyMessage,
        ),
      );
    }

    // One column on a phone, a grid on anything wider. Without this the card
    // art, which is pinned to a fixed aspect ratio, scales with the window and
    // a desktop window shows one enormous photo per row.
    return SliverPadding(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = AppLayout.columnsFor(width);

          if (columns == 1) {
            return SliverList.builder(
              itemCount: _destinations.length,
              itemBuilder: (context, index) => _resultCard(index),
            );
          }

          final tileWidth = width / columns;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppLayout.gridSpacing,
              mainAxisSpacing: AppLayout.gridSpacing,
              mainAxisExtent:
                  AppLayout.destinationTileHeight(context, tileWidth),
            ),
            itemCount: _destinations.length,
            itemBuilder: (context, index) => _resultCard(index),
          );
        },
      ),
    );
  }

  Widget _resultCard(int index) {
    final destination = _destinations[index];
    return DestinationCard(
      destination: destination,
      onTap: () => Navigator.pushNamed(
        context,
        "/destination_detail",
        arguments: destination,
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    var draftRegion = _selectedRegion;
    var draftMaxCost = _maxCost;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Shape your search",
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                              ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Combine a region and budget with your search or activity filter.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: draftRegion ?? "all",
                      decoration: const InputDecoration(
                        labelText: "Region",
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: "all",
                          child: Text("All regions"),
                        ),
                        ..._regions.map(
                          (region) => DropdownMenuItem(
                            value: region,
                            child: Text(region),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(
                          () => draftRegion = value == "all" ? null : value,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: draftMaxCost?.toString() ?? "any",
                      decoration: const InputDecoration(
                        labelText: "Maximum daily cost",
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "any",
                          child: Text("Any budget"),
                        ),
                        DropdownMenuItem(
                          value: "50000",
                          child: Text("Up to 50k XAF"),
                        ),
                        DropdownMenuItem(
                          value: "100000",
                          child: Text("Up to 100k XAF"),
                        ),
                        DropdownMenuItem(
                          value: "200000",
                          child: Text("Up to 200k XAF"),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(
                          () => draftMaxCost = value == null || value == "any"
                              ? null
                              : int.tryParse(value),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            child: const Text("Apply filters"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _selectedRegion = draftRegion;
        _maxCost = draftMaxCost;
      });
      _loadDestinations();
    }
  }

  Future<void> _showSortSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text("Sort places"),
              subtitle: Text("Choose what to prioritize"),
            ),
            ...[
              ("recommended", "Recommended", Icons.auto_awesome_outlined),
              ("cost_low", "Lowest cost", Icons.south_rounded),
              ("cost_high", "Highest cost", Icons.north_rounded),
              ("name", "Name A–Z", Icons.sort_by_alpha_rounded),
            ].map(
              (option) {
                final isSelected = option.$1 == _sortMode;
                return ListTile(
                  selected: isSelected,
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color:
                        isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  title: Text(option.$2),
                  trailing: Icon(option.$3, color: AppTheme.primary),
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _sortMode = selected;
        _destinations = _sortResults(_destinations);
      });
    }
  }
}

/// Carries the filter bar as a sliver so it can scroll out of the way.
///
/// The height is fixed — min and max extent are the same — because the bar
/// does not shrink as it leaves; it slides off whole and slides back whole.
class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget Function(BuildContext context, bool overlapsContent) builder;

  const _FilterBarDelegate({
    required this.extent,
    required this.builder,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      SizedBox.expand(child: builder(context, overlapsContent));

  @override
  bool shouldRebuild(_FilterBarDelegate oldDelegate) =>
      // The builder closes over the screen's state — the selected chip, the
      // result count, the sort label — so every rebuild of the screen has to
      // reach the header too. Comparing extents alone would freeze the count
      // at whatever it was when the bar was first laid out.
      true;
}
