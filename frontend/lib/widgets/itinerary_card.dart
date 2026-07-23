import "package:flutter/material.dart";
import "../models/itinerary.dart";

class ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final VoidCallback? onTap;
  final VoidCallback? onShare;

  const ItineraryCard({
    super.key,
    required this.itinerary,
    this.onTap,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final destCount = itinerary.destinations.length;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(itinerary.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$destCount destination(s)"),
            if (itinerary.startDate.isNotEmpty)
              Text("${itinerary.startDate} → ${itinerary.endDate}"),
          ],
        ),
        trailing: onShare != null
            ? IconButton(icon: const Icon(Icons.share), onPressed: onShare)
            : null,
        onTap: onTap,
      ),
    );
  }
}
