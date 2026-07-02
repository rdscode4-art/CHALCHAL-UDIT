import 'package:flutter/foundation.dart';

class RideRequestService {
  static final List<Map<String, dynamic>> _pendingRequests = [];

  static List<Map<String, dynamic>> get pendingRequests => _pendingRequests
      .map((request) => Map<String, dynamic>.from(request))
      .toList();

  static void queueRideRequest(Map<String, dynamic> request) {
    final rideId = request['rideId']?.toString() ?? request['_id']?.toString() ?? request['id']?.toString() ?? '';
    final queuedRequest = {
      ...request, // Keep all original properties like lat/lng, pickup, dropoff
      'rideId': rideId,
    };
    _pendingRequests.add(queuedRequest);
    debugPrint(
      'SUCCESS [QUEUE] Ride queued: ${queuedRequest['rideId']} for driver ${queuedRequest['driverId']}',
    );
    debugPrint('   - Fare: ${queuedRequest['fare']}');
    debugPrint('   - Distance: ${queuedRequest['distance']}');
    debugPrint('   - Duration: ${queuedRequest['duration']}');
  }

  /// Peek at the next request for [driverId] without removing it.
  static Map<String, dynamic>? peekRequestForDriver({
    required String driverId,
  }) {
    final idx = _pendingRequests.indexWhere((r) {
      final assignedDriverId =
          (r['assignedDriverId'] as String?)?.trim() ??
          (r['driverId'] as String?)?.trim() ??
          '';
      return assignedDriverId == driverId.trim();
    });
    if (idx == -1) return null;
    return Map<String, dynamic>.from(_pendingRequests[idx]);
  }

  static void removeRequestByRideId(String rideId) {
    _pendingRequests.removeWhere(
      (r) => (r['rideId'] as String?)?.trim() == rideId.trim(),
    );
  }

  static Map<String, dynamic>? popRequestForDriver({
    required String driverId,
    required String vehicleType,
  }) {
    // Add debugging
    debugPrint(
      '[MATCH_DEBUG] Searching for driverId="$driverId", vehicleType="$vehicleType"',
    );
    debugPrint(
      '[MATCH_DEBUG] Queue has ${_pendingRequests.length} requests',
    );

    for (var i = 0; i < _pendingRequests.length; i++) {
      final r = _pendingRequests[i];
      final assignedDriverId = (r['driverId'] as String?)?.trim() ?? '';
      final requestVehicleType = r['vehicleType'] as String? ?? '';
      final typeMatches = doesVehicleTypeMatch(vehicleType, requestVehicleType);

      debugPrint(
        '  Request $i: driverId="$assignedDriverId" (match=${assignedDriverId == driverId}), vehicleType="$requestVehicleType" (match=$typeMatches)',
      );
    }

    final idx = _pendingRequests.indexWhere((r) {
      final assignedDriverId = (r['driverId'] as String?)?.trim() ?? '';
      final requestVehicleType = r['vehicleType'] as String? ?? '';
      return assignedDriverId == driverId &&
          doesVehicleTypeMatch(vehicleType, requestVehicleType);
    });

    debugPrint('[MATCH_RESULT] Match index: $idx');

    if (idx == -1) return null;
    return _pendingRequests.removeAt(idx);
  }

  static bool doesVehicleTypeMatch(
    String selectedType,
    String driverVehicleType,
  ) {
    final sel = selectedType.trim().toLowerCase();
    final drv = driverVehicleType.trim().toLowerCase();
    if (sel == drv) return true;

    if (sel == 'bike') {
      return drv == 'bike';
    }
    if (sel == 'auto') {
      return drv == 'auto';
    }
    if (sel == 'ev') {
      return drv == 'ev';
    }
    if (sel == 'sedan') {
      return drv == 'sedan';
    }
    if (sel == 'suv') {
      return drv == 'suv';
    }

    return false;
  }

  /// Peek at pending requests matching [vehicleType] without removing.
  static List<Map<String, dynamic>> requestsForVehicleType(String vehicleType) {
    return _pendingRequests
        .where(
          (r) => doesVehicleTypeMatch(
            r['vehicleType'] as String? ?? '',
            vehicleType,
          ),
        )
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  static void clearQueue() {
    _pendingRequests.clear();
  }

  /// Remove any queued requests that were assigned to [driverId].
  static void removeRequestsForDriver(String driverId) {
    _pendingRequests.removeWhere((r) {
      final assignedDriverId = (r['driverId'] as String?)?.trim() ?? '';
      return assignedDriverId == driverId;
    });
  }

  /// Legacy compatibility for tests and older local-queue flows.
  static Map<String, dynamic>? popRequestForVehicleType(String vehicleType) {
    final idx = _pendingRequests.indexWhere((r) {
      final requestVehicleType = r['vehicleType'] as String? ?? '';
      return doesVehicleTypeMatch(vehicleType, requestVehicleType);
    });
    if (idx == -1) return null;
    return _pendingRequests.removeAt(idx);
  }
}
