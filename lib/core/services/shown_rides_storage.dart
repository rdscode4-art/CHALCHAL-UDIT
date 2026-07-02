import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists ride IDs for which the driver UI was already shown (dedupe guard).
class ShownRidesStorage {
  static const _shownKey = 'driver_shown_ride_ids';
  static const _ignoredKey = 'driver_ignored_ride_ids';

  // ── Shown rides (dedupe — prevents showing same ride popup twice) ──────────

  static Future<Set<String>> getShownRideIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shownKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> addShownRideId(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = await getShownRideIds();
    ids.add(rideId);
    await prefs.setString(_shownKey, jsonEncode(ids.toList()));
  }

  static Future<void> removeShownRideId(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = await getShownRideIds();
    ids.remove(rideId);
    await prefs.setString(_shownKey, jsonEncode(ids.toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shownKey);
  }

  // ── Ignored rides (driver explicitly pressed "Ignore") ────────────────────
  // Stored separately so ignored rides are never shown again across sessions.

  static Future<Set<String>> getIgnoredRideIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ignoredKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> addIgnoredRideId(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = await getIgnoredRideIds();
    ids.add(rideId);
    // Keep max 200 entries to prevent unbounded growth
    final trimmed = ids.length > 200
        ? ids.toList().sublist(ids.length - 200).toSet()
        : ids;
    await prefs.setString(_ignoredKey, jsonEncode(trimmed.toList()));
  }

  static Future<void> removeIgnoredRideId(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = await getIgnoredRideIds();
    ids.remove(rideId);
    await prefs.setString(_ignoredKey, jsonEncode(ids.toList()));
  }

  static Future<bool> isIgnored(String rideId) async {
    if (rideId.isEmpty) return false;
    final ids = await getIgnoredRideIds();
    return ids.contains(rideId);
  }

  static Future<void> clearIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ignoredKey);
  }
}
