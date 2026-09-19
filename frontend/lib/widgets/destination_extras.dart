import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";

import "../models/destination.dart";
import "../models/place_extras.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "../services/places_service.dart";
import "../utils/theme.dart";

/// Ground-level detail for a destination: what travellers rate it, how to get
/// there, and which services exist around it.
///
/// Each section loads independently. Amenity data comes from OpenStreetMap via
/// a free shared service that is sometimes slow, and there is no reason for
/// that to hold up the ratings or the nearby list.
class DestinationExtras extends StatefulWidget {
  final Destination destination;

  const DestinationExtras({super.key, required this.destination});

  @override
  State<DestinationExtras> createState() => _DestinationExtrasState();
}

class _DestinationExtrasState extends State<DestinationExtras> {
  final PlacesService _service = PlacesService();
  final ApiService _api = ApiService();

  RatingSummary _rating = RatingSummary.empty;
  List<NearbyPlace> _nearby = const [];
  List<AmenityGroup> _amenities = const [];

  bool _loadingAmenities = true;
  bool _savingRating = false;
  bool _openingNearby = false;

  @override
  void initState() {
    super.initState();
    _loadRating();
    _loadNearby();
    _loadAmenities();
  }

  Future<void> _loadRating() async {
    final token = context.read<AuthProvider>().token;
    try {
      final summary =
          await _service.fetchRating(widget.destination.id, token: token);
      if (mounted) setState(() => _rating = summary);
    } catch (_) {
      // A missing rating is not worth an error banner on a detail page.
    }
  }

  Future<void> _loadNearby() async {
    try {
      final places = await _service.fetchNearby(widget.destination.id);
      if (mounted) setState(() => _nearby = places);
    } catch (_) {
      // Leave the section hidden rather than showing a failure.
    }
  }

  Future<void> _loadAmenities() async {
    final groups = await _service.fetchAmenities(widget.destination.id);
    if (mounted) {
      setState(() {
        _amenities = groups;
        _loadingAmenities = false;
      });
    }
  }

  Future<void> _rate(int stars) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      _notify("Sign in to rate this place.");
      return;
    }
    if (_savingRating) return;

    setState(() => _savingRating = true);
    try {
      // Tapping the star you already chose withdraws the rating, which is the
      // only way to undo one without a separate control.
      final summary = _rating.mine == stars
          ? await _service.clearRating(
              token: token, destinationId: widget.destination.id)
          : await _service.setRating(
              token: token, destinationId: widget.destination.id, stars: stars);
      if (mounted) setState(() => _rating = summary);
    } catch (error) {
      _notify(error.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _savingRating = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _notify("Could not open that on this device.");
  }

  /// The detail route takes a whole [Destination], and the nearby list only
  /// carries a summary, so the full record is fetched before navigating.
  Future<void> _openNearby(NearbyPlace place) async {
    if (_openingNearby) return;
    setState(() => _openingNearby = true);
    try {
      final destination = await _api.getDestination(place.id);
      if (!mounted) return;
      Navigator.pushNamed(context, "/destination_detail",
          arguments: destination);
    } catch (_) {
      _notify("Could not open ${place.name}.");
    } finally {
      if (mounted) setState(() => _openingNearby = false);
    }
  }

  bool get _hasCoordinates =>
      widget.destination.latitude != 0 || widget.destination.longitude != 0;

  Future<void> _directions() async {
    final destination = widget.destination;
    final query = _hasCoordinates
        ? "${destination.latitude},${destination.longitude}"
        : Uri.encodeComponent("${destination.name}, ${destination.region}");
    await _open(
        Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$query"));
  }

  Future<void> _bookTaxi() async {
    final destination = widget.destination;
    // Yango is the ride-hailing service with the widest coverage in Cameroon.
    // Where it has not launched, the link still resolves to its site, so the
    // traveller is never left without an explanation.
    final uri = _hasCoordinates
        ? Uri.parse("https://yango.go.link/route?end-lat="
            "${destination.latitude}&end-lon=${destination.longitude}")
        : Uri.parse("https://yango.com");
    await _open(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ratingSection(),
        const SizedBox(height: 22),
        _travelActions(),
        if (_loadingAmenities || _amenities.isNotEmpty) ...[
          const SizedBox(height: 26),
          _amenitiesSection(),
        ],
        if (_nearby.isNotEmpty) ...[
          const SizedBox(height: 26),
          _nearbySection(),
        ],
      ],
    );
  }

  Widget _heading(String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: AppTheme.displayFontFamily,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _ratingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          "Traveller rating",
          subtitle: _rating.hasRatings
              ? "${_rating.averageLabel} out of 5 from ${_rating.countLabel}"
              : "No ratings yet. Be the first.",
        ),
        Row(
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                onPressed: _savingRating ? null : () => _rate(star),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                constraints: const BoxConstraints(),
                tooltip: _rating.mine == star
                    ? "Remove your rating"
                    : "Rate $star out of 5",
                icon: Icon(
                  (_rating.mine ?? 0) >= star
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 30,
                  color: AppTheme.accent,
                ),
              ),
            const SizedBox(width: 10),
            if (_rating.mine != null)
              Text(
                "Your rating",
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
          ],
        ),
      ],
    );
  }

  Widget _travelActions() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _directions,
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text("Get directions"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _bookTaxi,
            icon: const Icon(Icons.local_taxi_rounded, size: 18),
            label: const Text("Book a taxi"),
          ),
        ),
      ],
    );
  }

  Widget _amenitiesSection() {
    if (_loadingAmenities) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading("What is nearby"),
          const Center(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          "What is nearby",
          subtitle: "Within about 1.5 km, from OpenStreetMap.",
        ),
        ..._amenities.map(_amenityGroupTile),
      ],
    );
  }

  Widget _amenityGroupTile(AmenityGroup group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppTheme.primarySoft.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(group.icon, color: AppTheme.primaryDark),
          title: Text(
            group.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            group.items.length == 1
                ? "1 place"
                : "${group.items.length} places",
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          children: group.items.take(12).map(_amenityTile).toList(),
        ),
      ),
    );
  }

  Widget _amenityTile(Amenity amenity) {
    final details = <String>[
      amenity.kindLabel,
      amenity.distanceLabel,
      if (amenity.openingHours.isNotEmpty) amenity.openingHours,
    ];

    return ListTile(
      dense: true,
      title: Text(amenity.name),
      subtitle: Text(details.join("  ·  ")),
      trailing: IconButton(
        tooltip: "Show on the map",
        icon: const Icon(Icons.north_east_rounded, size: 18),
        onPressed: () =>
            _open(Uri.parse("https://www.google.com/maps/search/?api=1&query="
                "${amenity.latitude},${amenity.longitude}")),
      ),
    );
  }

  Widget _nearbySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading("Other spots worth a visit"),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _nearby.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _nearbyCard(_nearby[index]),
          ),
        ),
      ],
    );
  }

  Widget _nearbyCard(NearbyPlace place) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openNearby(place),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              place.distanceLabel,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (place.ratingCount > 0)
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 15, color: AppTheme.accent),
                  const SizedBox(width: 4),
                  Text(
                    "${place.ratingAverage.toStringAsFixed(1)}  ·  "
                    "${place.ratingCount}",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              )
            else
              Text(
                place.region,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
