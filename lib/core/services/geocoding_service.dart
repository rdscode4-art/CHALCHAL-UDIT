import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

/// Centralised reverse-geocoding helper used across the app.
///
/// Strategy (same priority as map_location_picker_screen):
///   1. `geocoding` package — device-native, no API key required.
///   2. Google Geocoding HTTP API — used only when an API key is available.
///   3. Returns `null` so callers can decide their own fallback text.
class GeocodingService {
  GeocodingService._();

  // ── Regex that matches strings like "Lat: 30.31479, Lng: 78.03401"
  static final _coordPattern = RegExp(
    r'Lat:\s*([-\d.]+),\s*Lng:\s*([-\d.]+)',
    caseSensitive: false,
  );

  // ── Detect whether a string looks like raw coordinates ──────────────────
  static bool looksLikeCoordinates(String text) {
    return _coordPattern.hasMatch(text) ||
        RegExp(r'^-?\d{1,3}\.\d+,\s*-?\d{1,3}\.\d+$').hasMatch(text.trim());
  }

  /// Extract [LatLng] from a string that contains "Lat: X, Lng: Y" or
  /// a bare "lat,lng" pair.  Returns `null` when the string does not match.
  static LatLng? extractLatLng(String text) {
    // "Lat: 30.31479, Lng: 78.03401"
    final match = _coordPattern.firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    // Bare "30.31479, 78.03401"
    final bare = RegExp(
      r'^(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)$',
    ).firstMatch(text.trim());
    if (bare != null) {
      final lat = double.tryParse(bare.group(1) ?? '');
      final lng = double.tryParse(bare.group(2) ?? '');
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    return null;
  }

  /// Reverse-geocode [latLng] to a human-readable address string.
  /// Returns `null` if every strategy fails.
  static Future<String?> reverseGeocode(LatLng latLng) async {
    // ── 1. Google Geocoding HTTP API (Prioritized for professional formatting) ────
    final key = AppConstants.googlePlacesApiKey;
    if (key.isNotEmpty && !key.startsWith('YOUR_')) {
      try {
        final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': key,
          'language': 'en',
        });
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final results = data['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final formatted =
                results.first['formatted_address'] as String? ?? '';
            if (formatted.isNotEmpty) return formatted;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [GeocodingService] Google API geocoding failed: $e');
      }
    }

    // ── 2. Native geocoding (Fallback with improved professional formatting) ──────
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      ).timeout(const Duration(seconds: 8));

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.name != null && p.name!.isNotEmpty && p.name != p.street) p.name!,
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null &&
              p.subLocality!.isNotEmpty &&
              p.subLocality != p.street)
            p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.subAdministrativeArea != null &&
              p.subAdministrativeArea!.isNotEmpty)
            p.subAdministrativeArea!,
          if (p.administrativeArea != null &&
              p.administrativeArea!.isNotEmpty &&
              p.administrativeArea != p.locality)
            p.administrativeArea!,
          if (p.postalCode != null && p.postalCode!.isNotEmpty) p.postalCode!,
          if (p.country != null && p.country!.isNotEmpty) p.country!,
        ];
        final seen = <String>{};
        final List<String> formattedParts = [];
        for (final part in parts) {
          if (seen.add(part.toLowerCase())) {
            formattedParts.add(part);
          }
        }
        if (formattedParts.isNotEmpty) {
          return formattedParts.join(', ');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [GeocodingService] Native geocoding failed: $e');
    }

    return null;
  }

  /// If [text] contains raw coordinates, resolve them to an address.
  /// Otherwise returns [text] unchanged.
  static Future<String> resolveIfCoordinates(
    String text, {
    String fallback = 'Unknown location',
  }) async {
    if (!looksLikeCoordinates(text)) return text;

    final latLng = extractLatLng(text);
    if (latLng == null) return fallback;

    return await reverseGeocode(latLng) ?? fallback;
  }
}
