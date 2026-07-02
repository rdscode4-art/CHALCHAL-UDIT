/// Canonical ride status values for the Chal Chal state machine.
class RideStatus {
  RideStatus._();

  static const pending = 'pending';
  static const assigned = 'assigned';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const ongoing = 'ongoing';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static String normalize(String? raw) =>
      (raw ?? '').toLowerCase().trim().replaceAll(RegExp(r'[-_\s]+'), '_');

  static bool isPending(String status) {
    final s = normalize(status);
    return s == pending || s == assigned || s == 'requested';
  }

  static bool isAccepted(String status) {
    final s = normalize(status);
    return s == accepted ||
        s == 'accept' ||
        s == 'driver_accepted' ||
        s == 'driveraccepted' ||
        s == 'confirmed' ||
        s == 'driver_accepted';
  }

  static bool isDeclined(String status) {
    final s = normalize(status);
    return s == declined || s == 'rejected';
  }

  static bool isOngoing(String status) {
    final s = normalize(status);
    return s == ongoing ||
        s == 'started' ||
        s == 'in_progress' ||
        s == 'near_destination' ||
        s == 'arriving';
  }

  static bool isCompleted(String status) {
    final s = normalize(status);
    return s == completed || s == 'ended' || s == 'finished';
  }

  static bool isCancelled(String status) {
    final s = normalize(status);
    return s == cancelled || s == 'canceled';
  }

  /// Driver should see an assign popup only for pending rides assigned to them.
  static bool isDriverAssignable(String status) {
    if (normalize(status).isEmpty) return true;
    return isPending(status);
  }

  /// Resolves status from explicit field + timestamp hints (acceptedAt, startedAt).
  static String resolveEffectiveStatus(
    Map<String, dynamic> raw,
    String parsedStatus,
  ) {
    // Check all possible field names
    final status =
        raw['status']?.toString() ??
        raw['rideStatus']?.toString() ??
        raw['ride_status']?.toString() ??
        raw['state']?.toString() ??
        parsedStatus;

    final s = normalize(status);

    if (isDeclined(s) ||
        isCancelled(s) ||
        isCompleted(s) ||
        isOngoing(s) ||
        isAccepted(s)) {
      return s;
    }

    final hasStartedAt =
        raw['startedAt'] != null && raw['startedAt'].toString().isNotEmpty;
    final hasAcceptedAt =
        raw['acceptedAt'] != null && raw['acceptedAt'].toString().isNotEmpty;

    if (hasStartedAt) return ongoing;
    if (hasAcceptedAt) return accepted;

    if (s.isEmpty || s == 'unknown') return pending;
    return s;
  }
}
