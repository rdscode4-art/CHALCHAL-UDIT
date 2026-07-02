import 'package:flutter/foundation.dart';
import '../services/ride_request_service.dart';

/// Utility class for debugging and monitoring the ride request queue
class QueueDebugger {
  /// Print detailed queue status to console
  static void printQueueStatus() {
    final queue = RideRequestService.pendingRequests;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('PENDING RIDES QUEUE STATUS');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('Total rides in queue: ${queue.length}');
    debugPrint('Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('');

    if (queue.isEmpty) {
      debugPrint('SUCCESS Queue is empty - no pending rides');
    } else {
      for (var i = 0; i < queue.length; i++) {
        final ride = queue[i];
        debugPrint('📍 Ride ${i + 1}/${queue.length}:');
        debugPrint('   🆔 Ride ID: ${ride['rideId']}');
        debugPrint('   🚗 Driver ID: ${ride['driverId']}');
        debugPrint('   🚙 Vehicle Type: ${ride['vehicleType']}');
        debugPrint('   📍 Pickup: ${ride['pickup']}');
        debugPrint('   🎯 Destination: ${ride['destination']}');
        debugPrint('   📏 Distance: ${ride['distance']}');
        debugPrint('   ⏱️  Duration: ${ride['duration']}');
        debugPrint('   Status: ${ride['status']}');
        debugPrint('   🕐 Requested: ${ride['requestedAt']}');

        // Calculate age
        try {
          final requestedAt = DateTime.parse(ride['requestedAt'].toString());
          final age = DateTime.now().difference(requestedAt);
          debugPrint('   ⏳ Age: ${age.inSeconds}s');
          if (age.inSeconds > 60) {
            debugPrint('   WARNING  WARNING: Ride older than 60 seconds!');
          }
        } catch (_) {
          debugPrint('   ⏳ Age: Unknown');
        }

        debugPrint('');
      }

      // Warnings
      if (queue.length > 1) {
        debugPrint('WARNING WARNING: Multiple rides in queue!');
        debugPrint('   This should not happen with the new fixes.');
        debugPrint('   Check if polling is properly stopped during rides.');
      }
    }

    debugPrint('═══════════════════════════════════════════');
  }

  /// Get queue statistics
  static Map<String, dynamic> getQueueStats() {
    final queue = RideRequestService.pendingRequests;

    int oldestAgeSeconds = 0;
    int newestAgeSeconds = 0;

    if (queue.isNotEmpty) {
      try {
        final ages = queue.map((ride) {
          final requestedAt = DateTime.parse(ride['requestedAt'].toString());
          return DateTime.now().difference(requestedAt).inSeconds;
        }).toList();

        ages.sort();
        oldestAgeSeconds = ages.last;
        newestAgeSeconds = ages.first;
      } catch (_) {
        // Ignore parsing errors
      }
    }

    return {
      'totalCount': queue.length,
      'isEmpty': queue.isEmpty,
      'hasMultiple': queue.length > 1,
      'oldestAgeSeconds': oldestAgeSeconds,
      'newestAgeSeconds': newestAgeSeconds,
      'hasStaleRides': oldestAgeSeconds > 60,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Check if queue is healthy
  static bool isQueueHealthy() {
    final queue = RideRequestService.pendingRequests;

    // Queue should have 0 or 1 ride
    if (queue.length > 1) {
      debugPrint('ERROR UNHEALTHY: Multiple rides in queue (${queue.length})');
      return false;
    }

    // No ride should be older than 60 seconds
    for (final ride in queue) {
      try {
        final requestedAt = DateTime.parse(ride['requestedAt'].toString());
        final age = DateTime.now().difference(requestedAt);
        if (age.inSeconds > 60) {
          debugPrint(
            'ERROR UNHEALTHY: Stale ride detected (${age.inSeconds}s old)',
          );
          return false;
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }

    debugPrint('SUCCESS HEALTHY: Queue is in good state');
    return true;
  }

  /// Get human-readable queue summary
  static String getQueueSummary() {
    final queue = RideRequestService.pendingRequests;

    if (queue.isEmpty) {
      return 'SUCCESS No pending rides';
    } else if (queue.length == 1) {
      return '📍 1 pending ride';
    } else {
      return 'WARNING  ${queue.length} pending rides (unusual)';
    }
  }

  /// Clear queue and log action
  static void clearQueueWithLog() {
    final count = RideRequestService.pendingRequests.length;
    RideRequestService.clearQueue();
    debugPrint('🧹 Cleared $count rides from queue');
  }
}
