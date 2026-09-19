/// Build-time configuration for the map surfaces.
///
/// The app uses OpenStreetMap via flutter_map, so no API key is required.
class MapsConfig {
  static const webApiKey = "";

  static bool get isConfigured => true;

  static bool get hasNativeApiKey => false;

  static const configurationTitle = "Interactive Cameroon Map";
  static const configurationMessage =
      "Discover destinations across all 10 regions of Cameroon.";
  static const configurationHint =
      "Click markers to explore locations, view trip routes, and plan your journey.";
}
