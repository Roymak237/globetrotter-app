import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../models/itinerary.dart";
import "../providers/auth_provider.dart";
import "../utils/theme.dart";
import "../widgets/itinerary_route_map.dart";
import "../widgets/share_itinerary_dialog.dart";

class ItineraryDetailScreen extends StatelessWidget {
  const ItineraryDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final itinerary = ModalRoute.of(context)!.settings.arguments as Itinerary;
    final tripDays = _tripDays(itinerary);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: AppTheme.appBarBackground,
        title: Text(itinerary.title),
        actions: [
          IconButton(
            tooltip: "Share trip",
            onPressed: () => _shareItinerary(context, itinerary),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TripHero(
              itinerary: itinerary,
              tripDays: tripDays,
            ),
            const SizedBox(height: 20),
            _TripOverview(
              itinerary: itinerary,
              tripDays: tripDays,
            ),
            if (itinerary.destinations.isNotEmpty) ...[
              const SizedBox(height: 18),
              ItineraryRouteMap(
                destinationNames: itinerary.destinations,
              ),
            ],
            const SizedBox(height: 18),
            _DetailSection(
              icon: Icons.route_rounded,
              label: "ROUTE / IN ORDER",
              child: itinerary.destinations.isEmpty
                  ? Text(
                      "No destinations added yet",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    )
                  : _RouteTimeline(destinations: itinerary.destinations),
            ),
            if (itinerary.notes.isNotEmpty) ...[
              const SizedBox(height: 18),
              _DetailSection(
                icon: Icons.sticky_note_2_outlined,
                label: "NOTES",
                child: Text(
                  itinerary.notes,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final changed = await Navigator.pushNamed(
                        context,
                        "/create_itinerary",
                        arguments: itinerary,
                      );
                      if (context.mounted && changed == true) {
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text("Edit trip"),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  tooltip: "Delete itinerary",
                  onPressed: () => _deleteItinerary(context, itinerary),
                  style: IconButton.styleFrom(
                    foregroundColor: AppTheme.secondary,
                    side: const BorderSide(color: AppTheme.secondary),
                    fixedSize: const Size(52, 52),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareItinerary(
    BuildContext context,
    Itinerary itinerary,
  ) async {
    final username = await showShareItineraryDialog(
      context,
      itineraryId: itinerary.id,
    );
    if (!context.mounted || username == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Shared with $username")),
    );
  }

  Future<void> _deleteItinerary(
      BuildContext context, Itinerary itinerary) async {
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Delete this trip?"),
            content: const Text(
              "This removes the itinerary from your saved journeys.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Keep it"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Delete"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await auth.deleteItinerary(itinerary.id);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text("Itinerary deleted")),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      }
    }
  }

  static int? _tripDays(Itinerary itinerary) {
    final start = DateTime.tryParse(itinerary.startDate);
    final end = DateTime.tryParse(itinerary.endDate);
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start).inDays + 1;
  }

  static String _dateRange(Itinerary itinerary) {
    final start = DateTime.tryParse(itinerary.startDate);
    final end = DateTime.tryParse(itinerary.endDate);
    if (start == null || end == null) {
      if (itinerary.startDate.isEmpty && itinerary.endDate.isEmpty) {
        return "Dates not set";
      }
      return "${itinerary.startDate}  →  ${itinerary.endDate}";
    }
    return "${_shortDate(start)}  →  ${_shortDate(end)}";
  }

  static String _shortDate(DateTime date) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }
}

class _TripHero extends StatelessWidget {
  final Itinerary itinerary;
  final int? tripDays;

  const _TripHero({
    required this.itinerary,
    required this.tripDays,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "FIELD NOTE",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            itinerary.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontFamily: AppTheme.displayFontFamily,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  ItineraryDetailScreen._dateRange(itinerary),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tripDays != null)
                Text(
                  "$tripDays day${tripDays == 1 ? "" : "s"}",
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripOverview extends StatelessWidget {
  final Itinerary itinerary;
  final int? tripDays;

  const _TripOverview({
    required this.itinerary,
    required this.tripDays,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OverviewTile(
            icon: Icons.place_outlined,
            label: "STOPS",
            value: "${itinerary.destinations.length}",
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OverviewTile(
            icon: Icons.schedule_outlined,
            label: "DURATION",
            value: tripDays == null ? "—" : "$tripDays days",
          ),
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OverviewTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 19),
          const SizedBox(height: 9),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.secondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  final List<String> destinations;

  const _RouteTimeline({required this.destinations});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < destinations.length; index++)
          _RouteStop(
            index: index,
            name: destinations[index],
            isLast: index == destinations.length - 1,
          ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  final int index;
  final String name;
  final bool isLast;

  const _RouteStop({
    required this.index,
    required this.name,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppTheme.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppTheme.accent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: AppTheme.displayFontFamily,
                      height: 1.2,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _DetailSection({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
