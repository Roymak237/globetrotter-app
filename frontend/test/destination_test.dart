import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/models/destination.dart";
import "package:globetrotter/utils/destination_cost.dart";

Map<String, dynamic> record({num? cost}) => {
      "id": "test-place",
      "name": "Yaoundé place",
      "region": "Centre",
      "description": "A place in Yaoundé.",
      "avg_cost_per_day": cost,
    };

void main() {
  test("location metadata and additional assets survive JSON round trips", () {
    final json = {
      ...record(cost: 2500),
      "address": "Bastos, Yaoundé",
      "location_notes": "Confirm the entrance before visiting.",
      "location_sources": ["https://example.org/location"],
      "image_asset": "tourist/city council.webp",
      "additional_image_assets": ["shopping/mokolo market.webp"],
      "latitude": 3.87,
      "longitude": 11.52,
    };
    final destination = Destination.fromJson(json);
    expect(destination.address, json["address"]);
    expect(destination.locationNotes, json["location_notes"]);
    expect(destination.locationSources, json["location_sources"]);
    expect(destination.additionalImageAssets, json["additional_image_assets"]);
    expect(destination.hasCoordinates, isTrue);
    expect(destination.hasCostEstimate, isTrue);
    expect(destination.avgCostPerDay, 2500);
    final restored = Destination.fromJson(destination.toJson());
    expect(restored.toJson(), destination.toJson());
    for (final key in json.keys) {
      expect(destination.toJson()[key], json[key], reason: key);
    }
  });

  test("legacy constructor retains defaults without signature breaks", () {
    final destination = Destination(
      id: "legacy",
      name: "Legacy",
      region: "Centre",
      description: "",
      tags: [],
      avgCostPerDay: 0,
      highlights: [],
    );
    expect(destination.hasCostEstimate, isTrue);
    expect(destination.toJson()["avg_cost_per_day"], 0);
    expect(destination.address, isEmpty);
    expect(destination.locationNotes, isEmpty);
    expect(destination.locationSources, isEmpty);
    expect(destination.additionalImageAssets, isEmpty);
  });

  test("null and absent cost remain unknown rather than free after round trip",
      () {
    for (final json in [record(), record()..remove("avg_cost_per_day")]) {
      final destination = Destination.fromJson(json);
      expect(destination.avgCostPerDay, 0);
      expect(destination.hasCostEstimate, isFalse);
      expect(destination.toJson()["avg_cost_per_day"], isNull);
      expect(
          Destination.fromJson(destination.toJson()).hasCostEstimate, isFalse);
      expect(destination.address, isEmpty);
      expect(destination.locationNotes, isEmpty);
      expect(destination.locationSources, isEmpty);
      expect(destination.additionalImageAssets, isEmpty);
    }
    expect(Destination.fromJson(record(cost: 0)).hasCostEstimate, isTrue);
  });

  test("missing or partial coordinates never count as a mapped location", () {
    for (final coordinates in <Map<String, dynamic>>[
      {},
      {"latitude": null, "longitude": null},
      {"latitude": 3.87},
      {"longitude": 11.52},
    ]) {
      final destination = Destination.fromJson({...record(), ...coordinates});
      expect(destination.hasCoordinates, isFalse);
      expect(
          Destination.fromJson(destination.toJson()).hasCoordinates, isFalse);
    }
  });

  test("unknown costs sort last in either direction, after known zero", () {
    for (final descending in [false, true]) {
      final destinations = [
        Destination.fromJson(record()),
        Destination.fromJson(record(cost: 5000)),
        Destination.fromJson(record(cost: 0)),
        Destination.fromJson(record(cost: 1000)),
        Destination.fromJson(record()),
      ]..sort((a, b) => compareDestinationCosts(a, b, descending: descending));
      expect(destinations.take(3).map((d) => d.avgCostPerDay),
          descending ? [5000, 1000, 0] : [0, 1000, 5000]);
      expect(destinations.skip(3).every((d) => !d.hasCostEstimate), isTrue);
    }
  });
}
