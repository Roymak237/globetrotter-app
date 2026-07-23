import "package:flutter/material.dart";
import "../models/destination.dart";

class DestinationCard extends StatelessWidget {
  final Destination destination;
  final VoidCallback? onTap;

  const DestinationCard({super.key, required this.destination, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tags = destination.tags.take(3).join(" • ");
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(destination.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(destination.region),
            const SizedBox(height: 4),
            Text(tags,
                style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ],
        ),
        trailing: Text(
          "${((destination.avgCostPerDay / 1000).toStringAsFixed(0))}k XAF",
          style: TextStyle(color: Theme.of(context).primaryColor),
        ),
        onTap: onTap,
      ),
    );
  }
}
