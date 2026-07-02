import 'package:shared_preferences/shared_preferences.dart';

/// Persists the active ride id from booking/assign through the trip lifecycle.
class ActiveRideStorage {
  static const _key = 'activeRideId';

  static Future<void> save(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, rideId);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
