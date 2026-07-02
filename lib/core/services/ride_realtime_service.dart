import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ride.dart';
import 'api_service.dart';

/// Single active-ride listener (Firestore-style) backed by periodic GET /rides/:id.
///
/// Primary UI updates should use this stream; push/FCM is supplementary only.
class RideRealtimeSubscription {
  final void Function() cancel;
  const RideRealtimeSubscription(this.cancel);
}

class RideRealtimeService {
  RideRealtimeService._();

  /// Polls [rideId] and invokes [onUpdate] when status or payload changes.
  static RideRealtimeSubscription listenToRide({
    required String rideId,
    required void Function(Ride ride) onUpdate,
    Duration interval = const Duration(seconds: 4),
    void Function(String? error)? onError,
    bool fireImmediately = true,
  }) {
    if (rideId.isEmpty) {
      return RideRealtimeSubscription(() {});
    }

    Timer? timer;
    String? lastFingerprint;
    var disposed = false;

    Future<void> tick() async {
      if (disposed) return;
      final res = await ApiService.getRide(rideId);
      if (disposed) return;

      if (!res.success) {
        onError?.call(res.errorMessage);
        return;
      }

      try {
        final ride = Ride.fromJson(res.data);
        final fingerprint =
            '${ride.status}|${ride.raw['acceptedAt']}|${ride.raw['startedAt']}|${ride.raw['completedAt']}';
        if (fingerprint == lastFingerprint) return;
        lastFingerprint = fingerprint;
        onUpdate(ride);
      } catch (e) {
        debugPrint('ERROR [RideRealtime] parse error: $e');
        onError?.call('Failed to parse ride');
      }
    }

    if (fireImmediately) {
      tick();
    }
    timer = Timer.periodic(interval, (_) => tick());

    return RideRealtimeSubscription(() {
      disposed = true;
      timer?.cancel();
    });
  }
}
