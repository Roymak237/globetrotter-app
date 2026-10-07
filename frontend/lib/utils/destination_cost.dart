import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../models/destination.dart";

/// A price with its thousands separated, in CFA francs.
///
/// "25000 XAF" is hard to read at a glance and easy to misread by a factor
/// of ten. The old label rounded to "25k XAF", which hid the difference
/// between 1000 and 1499 behind the same "1k".
String formatXaf(num amount) {
  final digits = amount.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write("\u202f");
    buffer.write(digits[i]);
  }
  return "$buffer XAF";
}

/// The heading above a price, saying what the figure actually buys.
///
/// Every tile used to read "EST. DAILY COST". Only four records are priced
/// by the day; the rest are one admission, one meal or one night, and a
/// museum's 2000 XAF entry shown as a daily cost overstates a day in
/// Yaounde several times over.
String destinationCostHeading(BuildContext context, Destination destination) {
  final isFrench = AppLocalizations.of(context).locale.languageCode == "fr";
  switch (destination.costBasis) {
    case "per_day":
      return isFrench ? "COÛT PAR JOUR" : "COST PER DAY";
    case "per_meal":
      return isFrench ? "REPAS POUR UNE PERSONNE" : "MEAL FOR ONE";
    case "per_visit":
      return isFrench ? "ENTRÉE PAR PERSONNE" : "ENTRY PER PERSON";
    case "per_night":
      return isFrench ? "PAR NUIT" : "PER NIGHT";
    case "per_trip":
      return isFrench ? "ACCÈS ET TRANSPORT" : "ACCESS AND TRANSPORT";
    case "free":
      return isFrench ? "ENTRÉE" : "ENTRY";
    default:
      return isFrench ? "COÛT" : "COST";
  }
}

/// The price itself, with the unit it is charged in.
///
/// The unit is repeated here because the chip on a browse card is shown
/// without the heading above it, and a bare "3 000 XAF" invites the reader
/// to assume it is a day's budget.
String destinationCostLabel(
  BuildContext context,
  Destination destination, {
  bool perDay = false,
}) {
  final isFrench = AppLocalizations.of(context).locale.languageCode == "fr";
  if (!destination.hasCostEstimate) {
    return isFrench ? "Non disponible" : "Not available";
  }
  // A known zero means the place costs nothing to visit, which is worth
  // saying outright. "0 XAF" reads like a missing value, which is exactly
  // the confusion the unknown/known split exists to avoid.
  if (destination.avgCostPerDay == 0) {
    return isFrench ? "Gratuit" : "Free";
  }

  final amount = formatXaf(destination.avgCostPerDay);
  if (!perDay) return amount;

  // `perDay` means "say what this buys", and it only means a day for the
  // handful of records that really are daily budgets.
  switch (destination.costBasis) {
    case "per_day":
      return "$amount / ${isFrench ? 'jour' : 'day'}";
    case "per_meal":
      return "$amount / ${isFrench ? 'repas' : 'meal'}";
    case "per_night":
      return "$amount / ${isFrench ? 'nuit' : 'night'}";
    case "per_visit":
      return "$amount / ${isFrench ? 'personne' : 'person'}";
    default:
      return amount;
  }
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
