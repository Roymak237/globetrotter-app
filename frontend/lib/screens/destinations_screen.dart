import "package:flutter/material.dart";
import "../models/destination.dart";
import "../services/api_service.dart";
import "../widgets/destination_card.dart";

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

  @override
  void initState() {
    super.initState();
    _loadDestinations();
  }

  Future<void> _loadDestinations({String? query, String? tag, String? region}) async {
    setState(() => _loading = true);
    try {
      final results = await _api.searchDestinations(
        query: query ?? _controller.text,
        tag: tag,
        region: region,
      );
      if (mounted) {
        setState(() {
          _destinations = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: "Search destinations",
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _loadDestinations(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: () async {
                  final region = await _showFilterDialog(context);
                  if (region != null) {
                    _loadDestinations(region: region);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _destinations.length,
                  itemBuilder: (context, index) {
                    final dest = _destinations[index];
                    return DestinationCard(
                      destination: dest,
                      onTap: () {},
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<String?> _showFilterDialog(BuildContext context) async {
    final regions = [
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
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Filter by Region"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ""),
            child: const Text("All"),
          ),
          ...regions.map(
            (r) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r),
              child: Text(r),
            ),
          ),
        ],
      ),
    );
  }
}
