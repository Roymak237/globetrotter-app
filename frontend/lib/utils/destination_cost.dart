import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";

String destinationCostLabel(
  BuildContext context,
  Destination destination, {
  bool perDay = false,
}) {
  final isFrench = AppLocalizations.of(context).locale.languageCode == "fr";
  if (!destination.hasCostEstimate) {
    return isFrench ? "Non disponible" : "Not available";
  }
  final cost = "${(destination.avgCostPerDay / 1000).toStringAsFixed(0)}k XAF";
  return perDay ? "$cost / ${isFrench ? 'jour' : 'day'}" : cost;
}

/// Unknown estimates sort last, regardless of the requested cost direction.
int compareDestinationCosts(
  Destination a,
  Destination b, {
  bool descending = false,
}) {
  if (a.hasCostEstimate != b.hasCostEstimate) {
    return a.hasCostEstimate ? -1 : 1;
  }
  if (!a.hasCostEstimate) return 0;
  return descending
      ? b.avgCostPerDay.compareTo(a.avgCostPerDay)
      : a.avgCostPerDay.compareTo(b.avgCostPerDay);
}
