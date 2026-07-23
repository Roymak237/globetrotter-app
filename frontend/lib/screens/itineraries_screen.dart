import "package:flutter/material.dart";
import "../models/itinerary.dart";
import "../providers/auth_provider.dart";
import "package:provider/provider.dart";

class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen> {
  List<Itinerary> _itineraries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItineraries();
  }

  Future<void> _loadItineraries() async {
    setState(() => _loading = true);
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
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.pushNamed(context, "/create_itinerary");
              _loadItineraries();
            },
            icon: const Icon(Icons.add),
            label: const Text("New Itinerary"),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _itineraries.isEmpty
                  ? const Center(
                      child: Text("No itineraries yet. Plan your first trip!"),
                    )
                  : ListView.builder(
                      itemCount: _itineraries.length,
                      itemBuilder: (context, index) {
                        final it = _itineraries[index];
                        return ListTile(
                          title: Text(it.title),
                          subtitle: Text(
                            "${it.startDate} → ${it.endDate}\n${it.destinations.join(", ")}",
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () async {
                              final username = await _showShareDialog(
                                context,
                                it.id,
                              );
                              if (username != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Shared with $username")),
                                );
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              "/itinerary_detail",
                              arguments: it,
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<String?> _showShareDialog(BuildContext context, String itineraryId) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Share Itinerary"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Username to share with"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final username = controller.text.trim();
              if (username.isNotEmpty) {
                try {
                  await context
                      .read<AuthProvider>()
                      .shareItinerary(
                        itineraryId: itineraryId,
                        sharedWith: username,
                      );
                  if (context.mounted) Navigator.pop(context, username);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                }
              }
            },
            child: const Text("Share"),
          ),
        ],
      ),
    );
  }
}
