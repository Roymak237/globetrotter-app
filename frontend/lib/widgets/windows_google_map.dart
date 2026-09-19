import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:latlong2/latlong.dart";
import "package:webview_windows/webview_windows.dart";

import "../models/destination.dart";
import "../utils/theme.dart";

/// Windows implementation of the live map surface using Edge WebView2 + Leaflet/OpenStreetMap.
class WindowsGoogleMap extends StatefulWidget {
  final List<Destination> destinations;
  final Destination? selectedDestination;
  final LatLng? currentLocation;
  final List<LatLng> routePoints;
  final ValueChanged<Destination>? onDestinationSelected;

  const WindowsGoogleMap({
    super.key,
    required this.destinations,
    this.selectedDestination,
    this.currentLocation,
    this.routePoints = const [],
    this.onDestinationSelected,
  });

  @override
  State<WindowsGoogleMap> createState() => _WindowsGoogleMapState();
}

class _WindowsGoogleMapState extends State<WindowsGoogleMap> {
  WebviewController? _controller;
  StreamSubscription<dynamic>? _messageSubscription;
  String? _error;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _startMap();
  }

  @override
  void didUpdateWidget(covariant WindowsGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isReady) return;

    if (widget.selectedDestination?.id != oldWidget.selectedDestination?.id) {
      _runMapScript(
        "window.globetrotterMap.setSelected(${jsonEncode(widget.selectedDestination?.id)});",
      );
    }
    if (widget.currentLocation != oldWidget.currentLocation &&
        widget.currentLocation != null) {
      final location = widget.currentLocation!;
      _runMapScript(
        "window.globetrotterMap.setCurrentLocation(${location.latitude}, ${location.longitude});",
      );
    }
  }

  Future<void> _startMap() async {
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        throw StateError(
          "Microsoft Edge WebView2 Runtime is required to display the map on Windows.",
        );
      }

      final controller = WebviewController();
      await controller.initialize();
      _messageSubscription = controller.webMessage.listen(_handleMapMessage);
      await controller.setBackgroundColor(const Color(0xFFE8F2EC));
      await controller.loadStringContent(_mapDocument());

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    }
  }

  void _handleMapMessage(dynamic message) {
    if (message is! Map) return;
    final type = message["type"];
    if (type == "map-ready") {
      if (mounted) setState(() => _isReady = true);
      return;
    }
    if (type == "destination-selected") {
      final id = message["id"]?.toString();
      if (id == null) return;
      for (final destination in widget.destinations) {
        if (destination.id.toString() == id) {
          widget.onDestinationSelected?.call(destination);
          return;
        }
      }
      return;
    }
    if (type == "map-error" && mounted) {
      setState(
          () => _error = message["message"]?.toString() ?? "The map could not load.");
    }
  }

  void _runMapScript(String script) {
    unawaited(_controller?.executeScript(script));
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _MapError(message: _error!);
    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Webview(controller),
          if (!_isReady)
            const ColoredBox(
              color: Color(0xFFE8F2EC),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  String _mapDocument() {
    final mapData = <String, dynamic>{
      "destinations": widget.destinations
          .map(
            (destination) => <String, dynamic>{
              "id": destination.id.toString(),
              "name": destination.name,
              "region": destination.region,
              "lat": destination.latitude,
              "lng": destination.longitude,
            },
          )
          .toList(),
      "selectedId": widget.selectedDestination?.id.toString(),
      "currentLocation": _locationJson(widget.currentLocation),
      "route": widget.routePoints
          .map((point) =>
              <String, double>{"lat": point.latitude, "lng": point.longitude})
          .toList(),
    };
    final encodedData = jsonEncode(mapData).replaceAll("</", "<\\/");

    return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<style>
html, body, #map { height: 100%; width: 100%; margin: 0; padding: 0; }
body { background: #e8f2ec; font-family: Arial, sans-serif; }
</style></head><body><div id="map"></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
(() => {
  const state = $encodedData;
  const map = L.map('map').setView([3.848, 11.5021], 7);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
    maxZoom: 19
  }).addTo(map);
  const markers = {};
  const markerLayer = L.layerGroup().addTo(map);
  const routeLayer = L.layerGroup().addTo(map);
  const currentLayer = L.layerGroup().addTo(map);
  let currentMarker = null;
  const send = (payload) => window.chrome?.webview?.postMessage(payload);

  window.globetrotterMap = {
    setSelected: (id) => {
      Object.values(markers).forEach(m => m.setOpacity(1));
      if (id && markers[id]) {
        markers[id].setOpacity(0.8);
        markers[id].openPopup();
      }
    },
    setCurrentLocation: (lat, lng, pan = true) => {
      const ll = L.latLng(lat, lng);
      if (!currentMarker) {
        currentMarker = L.circleMarker(ll, {
          radius: 10, fillColor: '#2563eb', color: '#ffffff', weight: 3, opacity: 1, fillOpacity: 1
        }).addTo(currentLayer);
      } else {
        currentMarker.setLatLng(ll);
      }
      if (pan) map.setView(ll, 15);
    }
  };

  state.destinations.forEach((place) => {
    const marker = L.marker([place.lat, place.lng])
      .bindPopup('<strong>' + place.name.replace(/</g, '&lt;') + '</strong><br>' + place.region.replace(/</g, '&lt;'))
      .addTo(markerLayer);
    marker.on('click', () => send({type: 'destination-selected', id: place.id}));
    markers[place.id] = marker;
  });

  if (state.route.length > 1) {
    L.polyline(state.route.map(p => L.latLng(p.lat, p.lng)), {
      color: '#d97706', weight: 5, opacity: 0.9
    }).addTo(routeLayer);
  }

  if (state.currentLocation) {
    window.globetrotterMap.setCurrentLocation(state.currentLocation.lat, state.currentLocation.lng, false);
  }

  if (state.selectedId) window.globetrotterMap.setSelected(state.selectedId);
  send({type: 'map-ready'});

  window.addEventListener('error', (event) => send({type: 'map-error', message: event.message || 'The map could not load.'}));
})();
</script></body></html>''';
  }

  Map<String, double>? _locationJson(LatLng? location) => location == null
      ? null
      : <String, double>{"lat": location.latitude, "lng": location.longitude};

  String _cleanError(Object error) =>
      error.toString().replaceFirst("Bad state: ", "");
}

class _MapError extends StatelessWidget {
  final String message;

  const _MapError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8F2EC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: AppTheme.primary, size: 34),
          const SizedBox(height: 12),
          const Text(
            "The map could not start",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.primaryDark, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
