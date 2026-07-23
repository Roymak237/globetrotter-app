import "package:flutter/material.dart";
import "../models/itinerary.dart";
import "../providers/auth_provider.dart";
import "package:provider/provider.dart";

class ItineraryDetailScreen extends StatelessWidget {
  const ItineraryDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final itinerary = ModalRoute.of(context)!.settings.arguments as Itinerary;
    return Scaffold(
      appBar: AppBar(title: Text(itinerary.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Region", style: Theme.of(context).textTheme.titleSmall),
            Text(itinerary.destinations.join(", ")),
            const SizedBox(height: 12),
            Text("Dates", style: Theme.of(context).textTheme.titleSmall),
            Text("${itinerary.startDate} → ${itinerary.endDate}"),
            const SizedBox(height: 12),
            if (itinerary.notes.isNotEmpty) ...[
              Text("Notes", style: Theme.of(context).textTheme.titleSmall),
              Text(itinerary.notes),
            ],
            const Spacer(),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, "/create_itinerary",
                        arguments: itinerary);
                  },
                  child: const Text("Edit"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Delete"),
                            content: const Text(
                                "Are you sure you want to delete this itinerary?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("Delete"),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                    if (confirm) {
                      try {
                        await context
                            .read<AuthProvider>()
                            .deleteItinerary(itinerary.id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Itinerary deleted")),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Error: $e")),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Delete", style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
