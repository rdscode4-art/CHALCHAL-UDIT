import 'package:shared_preferences/shared_preferences.dart';

/// Persists login session locally so the user/driver stays logged in
/// across app restarts.
class SessionService {
  static const _keyRole = 'session_role'; // 'user' | 'driver'
  static const _keyId = 'session_id';
  static const _keyName = 'session_name';
  static const _keyPhone = 'session_phone';
  static const _keyVehicle = 'session_vehicle'; // driver only
  static const _keyVehicleType = 'session_vehicle_type'; // driver only
  static const _keyVerificationStatus = 'session_verification_status';
  static const _keyRejectionReason = 'session_rejection_reason';
  static const _keyExperience = 'session_experience';
  static const _keyRating = 'session_rating';
  static const _keyVehicleModel = 'session_vehicle_model';
  static const _keyVehicleColor = 'session_vehicle_color'; // driver only
  static const _keyToken = 'session_auth_token'; // Authentication token

  // ── Zone fields (NEW) ─────────────────────────────────────────────────────
  static const _keyZoneId = 'session_zone_id';
  static const _keyZoneName = 'session_zone_name';
  static const _keyIsInsideZone = 'session_is_inside_zone';
  static const _keyLastZoneCheckTime = 'session_last_zone_check_time';

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<void> saveUser({
    required String id,
    required String name,
    required String phone,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, 'user');
    await prefs.setString(_keyId, id);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyPhone, phone);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyToken, token);
    }
  }

  static Future<void> saveDriver({
    required String id,
    required String name,
    required String phone,
    required String vehicleNumber,
    String vehicleType = 'Auto',
    String verificationStatus = 'pending',
    String rejectionReason = '',
    String experience = '—',
    String rating = '4.9',
    String vehicleModel = '',
    String vehicleColor = '',
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, 'driver');
    await prefs.setString(_keyId, id);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyPhone, phone);
    await prefs.setString(_keyVehicle, vehicleNumber);
    await prefs.setString(_keyVehicleType, vehicleType);
    await prefs.setString(_keyVerificationStatus, verificationStatus);
    await prefs.setString(_keyRejectionReason, rejectionReason);
    await prefs.setString(_keyExperience, experience);
    await prefs.setString(_keyRating, rating);
    await prefs.setString(_keyVehicleModel, vehicleModel);
    await prefs.setString(_keyVehicleColor, vehicleColor);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyToken, token);
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  static Future<Map<String, String>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyId) ?? '';
    final defaultStatus = (id.startsWith('d') && id.length <= 3)
        ? 'verified'
        : 'pending';
    return {
      'role': prefs.getString(_keyRole) ?? '',
      'id': id,
      'name': prefs.getString(_keyName) ?? '',
      'phone': prefs.getString(_keyPhone) ?? '',
      'vehicleNumber': prefs.getString(_keyVehicle) ?? '',
      'vehicleType': prefs.getString(_keyVehicleType) ?? 'Auto',
      'verificationStatus':
          prefs.getString(_keyVerificationStatus) ?? defaultStatus,
      'rejectionReason': prefs.getString(_keyRejectionReason) ?? '',
      'experience': prefs.getString(_keyExperience) ?? '—',
      'rating': prefs.getString(_keyRating) ?? '4.9',
      'vehicleModel': prefs.getString(_keyVehicleModel) ?? '',
      'vehicleColor': prefs.getString(_keyVehicleColor) ?? '',
      'token': prefs.getString(_keyToken) ?? '',
      // Zone fields (NEW)
      'zoneId': prefs.getString(_keyZoneId) ?? '',
      'zoneName': prefs.getString(_keyZoneName) ?? '',
      'isInsideZone': prefs.getString(_keyIsInsideZone) ?? 'true',
    };
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyId);
  }

  static Future<String?> getDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyRole) != 'driver') return null;
    return prefs.getString(_keyId);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  // ── Zone methods (NEW) ────────────────────────────────────────────────────

  /// Save zone information for driver
  static Future<void> saveZoneInfo({
    required String zoneId,
    required String zoneName,
    required bool isInsideZone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyZoneId, zoneId);
    await prefs.setString(_keyZoneName, zoneName);
    await prefs.setString(_keyIsInsideZone, isInsideZone.toString());
    await prefs.setString(
      _keyLastZoneCheckTime,
      DateTime.now().toIso8601String(),
    );
  }

  /// Get saved zone information
  static Future<Map<String, dynamic>> getZoneInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'zoneId': prefs.getString(_keyZoneId) ?? '',
      'zoneName': prefs.getString(_keyZoneName) ?? '',
      'isInsideZone': prefs.getBool(_keyIsInsideZone) ?? true,
      'lastCheckTime': prefs.getString(_keyLastZoneCheckTime),
    };
  }

  /// Get current zone ID
  static Future<String?> getZoneId() async {
    final prefs = await SharedPreferences.getInstance();
    final zoneId = prefs.getString(_keyZoneId);
    return zoneId?.isNotEmpty ?? false ? zoneId : null;
  }

  /// Clear zone information on logout
  static Future<void> clearZoneInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyZoneId);
    await prefs.remove(_keyZoneName);
    await prefs.remove(_keyIsInsideZone);
    await prefs.remove(_keyLastZoneCheckTime);
  }

  // ── Clear (logout) ────────────────────────────────────────────────────────

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Clear all local stored data immediately (for development/testing)
  static Future<void> clearAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
