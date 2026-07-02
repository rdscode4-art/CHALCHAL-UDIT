class AppConstants {
  // ── Google Maps / Places / Directions API key ─────────────────────────────
  // This key is registered for Maps SDK (Android + iOS), Directions API,
  // Geocoding API, and Places API in the Google Cloud Console.
  static const String mapsApiKey = 'AIzaSyBJ2UDH5qyj_6kwMGYvu5WKj2MlnLgRP_E';

  // Legacy alias kept so existing callers (user_home_screen, geocoding_service,
  // select_ride_screen) continue to compile without change.
  static const String googlePlacesApiKey = mapsApiKey;

  // ── Backend base URL ───────────────────────────────────────────────────────
  static const String apiBaseUrl = 'https://chalchal.ridealdigitalseva.com';
}
