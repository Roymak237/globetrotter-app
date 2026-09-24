import "dart:async";

import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";
import "../models/shared_location.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "../services/location_service.dart";
import "../utils/theme.dart";
import "../widgets/destination_map.dart";
import "../widgets/map_action_button.dart";
import "../widgets/state_views.dart";

class MapScreen extends StatefulWidget {
  final bool isActive;

  const MapScreen({
    super.key,
    this.isActive = true,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Whether the device has already been asked for location permission.
  ///
  /// Stored so the map asks once and then respects the answer. Re-prompting on
  /// every visit is the behaviour that trains people to hit "deny" reflexively.
  static const _promptedKey = "tracker.permission_prompted";

  /// Whether the traveller chose to share their position with their groups.
  ///
  /// Separate from the OS permission on purpose: allowing the app to see where
  /// you are is not the same as agreeing to broadcast it, so the two are asked
  /// for separately and this one defaults to off.
  static const _sharingKey = "tracker.share_with_groups";

  /// The position stream fires every few metres. Publishing at that rate would
  /// spend battery and data on a dot nobody is watching that closely.
  static const _publishInterval = Duration(seconds: 20);

  static const _companionInterval = Duration(seconds: 45);

  final _api = ApiService();
  final _locationService = LocationService();
  MapController? _mapController;
  List<Destination> _destinations = [];
  Destination? _selectedDestination;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionSub;
  Timer? _companionTimer;
  List<SharedLocation> _companions = const [];
  DateTime? _lastPublishedAt;
  bool _following = false;
  bool _sharing = false;
  bool _loading = false;
  bool _locating = false;
  bool _hasLoaded = false;
  String? _error;

  bool get _tracking => _positionSub != null;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadDestinations();
      _bootstrapLocation();
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && !_hasLoaded) {
      _loadDestinations();
      _bootstrapLocation();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _companionTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final destinations = await _api.searchDestinations();
      if (!mounted) return;
      setState(() {
        _destinations = destinations;
        _selectedDestination = destinations.isEmpty ? null : destinations.first;
        _loading = false;
        _hasLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
        _error = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  void _selectDestination(Destination destination) {
    setState(() {
      _selectedDestination = destination;
      // Moving to a destination is a request to look somewhere else, so the
      // camera stops chasing the traveller rather than fighting them for it.
      _following = false;
    });
    final location = destination.hasCoordinates
        ? LatLng(destination.latitude!, destination.longitude!)
        : null;
    if (location != null) {
      _mapController?.move(location, 14.5);
    }
  }

  void _handleMapCreated(MapController controller) {
    _mapController = controller;
    final location = _currentLocation;
    if (location != null) {
      controller.move(location, 15);
    }
  }

  // ------------------------------------------------------------- tracking

  /// Restores the saved choices and starts tracking if that is already allowed.
  ///
  /// Everything here is silent. Opening a map is not the moment to interrupt
  /// someone with an error about location services; the crosshair button
  /// reports properly when it is actually pressed.
  Future<void> _bootstrapLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sharing = prefs.getBool(_sharingKey) ?? false;
      if (mounted && sharing) setState(() => _sharing = true);

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied &&
          !(prefs.getBool(_promptedKey) ?? false)) {
        await prefs.setBool(_promptedKey, true);
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await _startTracking();
      }
    } catch (_) {
      // Location is unavailable on this device or platform. The map still works.
    }
    await _refreshCompanions();
    _companionTimer ??= Timer.periodic(
      _companionInterval,
      (_) => _refreshCompanions(),
    );
  }

  /// Subscribes to the device's position stream. Throws a readable message if
  /// the traveller has to change something before that can happen.
  Future<void> _startTracking() async {
    if (_tracking) return;
    final localizations = AppLocalizations.of(context);

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(localizations.trackerServiceOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception(localizations.trackerPermissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(localizations.trackerPermissionBlocked);
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen(
      _handlePosition,
      onError: (_) {
        // A single bad fix is normal indoors. The stream keeps running and the
        // map simply holds the last known position until the next good one.
      },
    );
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    final location = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = location;
      _locating = false;
    });
    if (_following) {
      _mapController?.move(location, 15);
    }
    _publishIfSharing(position);
  }

  Future<void> _publishIfSharing(Position position) async {
    if (!_sharing) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final now = DateTime.now();
    final last = _lastPublishedAt;
    if (last != null && now.difference(last) < _publishInterval) return;
    _lastPublishedAt = now;

    try {
      await _locationService.publish(
        token: token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      // One dropped update is not worth an alert; the next fix retries.
    }
  }

  Future<void> _refreshCompanions() async {
    if (!mounted) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final companions = await _locationService.fetchCompanions(token);
      if (mounted) setState(() => _companions = companions);
    } catch (_) {
      // Leave whatever is already on the map rather than blanking it out over
      // one failed poll.
    }
  }

  /// The crosshair button: start tracking if it is not running, otherwise turn
  /// camera-following on or off.
  Future<void> _toggleFollow() async {
    if (_locating) return;

    if (_tracking) {
      setState(() => _following = !_following);
      final location = _currentLocation;
      if (_following && location != null) {
        _mapController?.move(location, 15);
      }
      return;
    }

    setState(() => _locating = true);
    try {
      await _startTracking();
      if (mounted) setState(() => _following = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", "")),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // -------------------------------------------------------------- sharing

  Future<void> _setSharing(bool enabled) async {
    final localizations = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthProvider>().token;

    if (enabled && token == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.trackerSignInRequired)),
      );
      return;
    }

    if (enabled) {
      try {
        await _startTracking();
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst("Exception: ", "")),
          ),
        );
        return;
      }
    }

    if (mounted) setState(() => _sharing = enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sharingKey, enabled);
    } catch (_) {
      // The switch still applies for this session even if it cannot be saved.
    }

    if (!enabled && token != null) {
      // Switching off has to reach the server, not just the UI. Otherwise the
      // last position would sit there visible to the group for another half
      // hour after the traveller believed they had stopped.
      _lastPublishedAt = null;
      try {
        await _locationService.stopSharing(token);
      } catch (_) {
        // The stored position expires on its own shortly anyway.
      }
    }
  }

  Future<void> _eraseStoredLocation() async {
    final localizations = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    await _setSharing(false);
    try {
      await _locationService.stopSharing(token);
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.trackerErased)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst("Exception: ", "")),
        ),
      );
    }
  }

  void _openTrackerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (sheetContext) => _TrackerSheet(
        sharing: _sharing,
        companions: _companions,
        onSharingChanged: (value) async {
          Navigator.of(sheetContext).pop();
          await _setSharing(value);
        },
        onErase: () async {
          Navigator.of(sheetContext).pop();
          await _eraseStoredLocation();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (!widget.isActive) return const SizedBox.expand();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.brand,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.secondary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localizations.mapHeading,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                                height: 1,
                              ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, "/itineraries"),
                icon: const Icon(Icons.route_rounded, size: 18),
                label: Text(localizations.myTrips),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? AppLoadingView(message: localizations.mapLoading)
              : _error != null
                  ? ErrorStateView(
                      title: localizations.mapErrorTitle,
                      message: _error!,
                      onRetry: _loadDestinations,
                    )
                  : _buildMap(context),
        ),
      ],
    );
  }

  Widget _buildMap(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mappedDestinations = _destinations
        .where((destination) => destination.hasCoordinates)
        .toList();

    if (mappedDestinations.isEmpty) {
      return EmptyStateView(
        icon: Icons.location_off_outlined,
        title: localizations.noMappedPlaces,
        message: localizations.noMappedPlacesMessage,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: DestinationMap(
              destinations: mappedDestinations,
              selectedDestination: _selectedDestination,
              currentLocation: _currentLocation,
              companions: _companions,
              followLocation: _following,
              onMapCreated: _handleMapCreated,
              onDestinationSelected: _selectDestination,
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 28,
          child: interceptMapOverlay(
              _MapCountPill(count: mappedDestinations.length)),
        ),
        Positioned(
          top: 14,
          right: 28,
          child: interceptMapOverlay(
            Column(
              children: [
                MapActionButton(
                  locating: _locating,
                  hasCurrentLocation: _currentLocation != null,
                  following: _following,
                  semanticLabel: _following
                      ? localizations.trackerStopFollowing
                      : localizations.trackerFollowMe,
                  onPressed: _toggleFollow,
                ),
                const SizedBox(height: 10),
                _TrackerButton(
                  sharing: _sharing,
                  companionCount: _companions.length,
                  semanticLabel: localizations.trackerOptions,
                  onPressed: _openTrackerSheet,
                ),
              ],
            ),
          ),
        ),
        if (_selectedDestination != null)
          Positioned(
            left: 28,
            right: 28,
            bottom: 18,
            child: interceptMapOverlay(
              _SelectedDestinationCard(
                destination: _selectedDestination!,
                onOpen: () => Navigator.pushNamed(
                  context,
                  "/destination_detail",
                  arguments: _selectedDestination,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapCountPill extends StatelessWidget {
  final int count;

  const _MapCountPill({required this.count});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          "$count mapped place${count == 1 ? "" : "s"}",
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SelectedDestinationCard extends StatelessWidget {
  final Destination destination;
  final VoidCallback onOpen;

  const _SelectedDestinationCard({
    required this.destination,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      elevation: 5,
      shadowColor: AppTheme.primaryDark.withValues(alpha: 0.18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.place_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontFamily: AppTheme.displayFontFamily,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${destination.region}  •  Tap to open field guide",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the live-location panel, and doubles as the indicator for whether
/// sharing is currently on.
///
/// Anything that broadcasts your position needs a permanently visible "off",
/// so this sits on the map rather than being buried in a settings page.
class _TrackerButton extends StatelessWidget {
  final bool sharing;
  final int companionCount;
  final String semanticLabel;
  final VoidCallback onPressed;

  const _TrackerButton({
    required this.sharing,
    required this.companionCount,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: sharing ? AppTheme.indigo : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        shadowColor: AppTheme.primaryDark.withValues(alpha: 0.2),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  sharing
                      ? Icons.share_location_rounded
                      : Icons.location_off_rounded,
                  color: sharing ? Colors.white : AppTheme.textSecondary,
                  size: 22,
                ),
                if (companionCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$companionCount",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sharing controls: one switch, a plain statement of what it does, the
/// list of who can currently be seen, and a way to erase the stored position.
class _TrackerSheet extends StatelessWidget {
  final bool sharing;
  final List<SharedLocation> companions;
  final ValueChanged<bool> onSharingChanged;
  final VoidCallback onErase;

  const _TrackerSheet({
    required this.sharing,
    required this.companions,
    required this.onSharingChanged,
    required this.onErase,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.trackerTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: AppTheme.displayFontFamily,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: sharing,
              onChanged: onSharingChanged,
              activeThumbColor: AppTheme.primary,
              title: Text(localizations.trackerSharingTitle),
              subtitle: Text(
                sharing
                    ? localizations.trackerSharingOn
                    : localizations.trackerSharingOff,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: sharing ? AppTheme.success : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              localizations.trackerSharingExplainer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              localizations.trackerCompanionsHeading,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            if (companions.isEmpty)
              Text(
                localizations.trackerCompanionsEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final companion in companions)
                    Chip(
                      avatar: const Icon(
                        Icons.person_pin_circle_rounded,
                        size: 18,
                        color: AppTheme.indigo,
                      ),
                      label: Text(companion.displayName),
                      backgroundColor: AppTheme.background,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onErase,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(localizations.trackerErase),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
