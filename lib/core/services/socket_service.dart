import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/app_constants.dart';

/// Singleton Socket.IO client.
///
/// Emits:
///   • `join_ride`       — join a ride room
///   • `leave_ride`      — leave a ride room
///   • `update_location` — driver sends GPS { rideId, lat, lng }
///   • `status_changed`  — status change notification { rideId, status }
///
/// Listens:
///   • `location_updated`         — driver location update → user map
///   • `status_updated`           — ride status change
///   • `connect` / `disconnect`   — connection events
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  // ── Connection ─────────────────────────────────────────────────────────────

  void connect() {
    if (socket != null && socket!.connected) {
      debugPrint('🔌 Socket already connected');
      return;
    }

    final url = AppConstants.apiBaseUrl;
    debugPrint('🔌 Connecting to socket server at $url…');

    socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling']) // fallback to polling
          .enableAutoConnect()
          .enableForceNew()
          .setTimeout(10000)
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(5)
          .build(),
    );

    socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('✅ Socket connected');
    });

    socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('❌ Socket disconnected');
    });

    socket!.onConnectError((data) {
      debugPrint('⚠️ Socket connect error: $data');
    });

    socket!.onReconnect((_) {
      _isConnected = true;
      debugPrint('🔄 Socket reconnected');
    });

    socket!.onError((data) {
      debugPrint('⚠️ Socket error: $data');
    });
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
    _isConnected = false;
    debugPrint('🔌 Socket connection closed manually');
  }

  // ── Room management ────────────────────────────────────────────────────────

  void joinRide(String rideId) {
    if (rideId.isEmpty) return;
    if (socket == null || !socket!.connected) connect();
    debugPrint('👥 Joining ride room: $rideId');
    socket?.emit('join_ride', {'rideId': rideId});
  }

  /// Driver joins their personal room so the server can push ride assignments.
  void joinDriverRoom(String driverId) {
    if (driverId.isEmpty) return;
    if (socket == null || !socket!.connected) connect();
    debugPrint('👥 Joining driver room: $driverId');
    socket?.emit('join_driver', {'driverId': driverId});
    socket?.emit('driver_online', {'driverId': driverId});
  }

  /// Driver leaves personal room on going offline.
  void leaveDriverRoom(String driverId) {
    if (driverId.isEmpty) return;
    if (socket != null && socket!.connected) {
      debugPrint('👥 Leaving driver room: $driverId');
      socket?.emit('leave_driver', {'driverId': driverId});
      socket?.emit('driver_offline', {'driverId': driverId});
    }
  }

  void leaveRide(String rideId) {
    if (rideId.isEmpty) return;
    if (socket != null && socket!.connected) {
      debugPrint('👥 Leaving ride room: $rideId');
      socket?.emit('leave_ride', {'rideId': rideId});
    }
  }

  // ── Emit ───────────────────────────────────────────────────────────────────

  /// Driver → server: continuous GPS update.
  void emitLocation({
    required String rideId,
    required double lat,
    required double lng,
  }) {
    if (socket != null && socket!.connected) {
      socket?.emit('update_location', {
        'rideId': rideId,
        'lat': lat,
        'lng': lng,
      });
      debugPrint('📤 Location emitted: ($lat, $lng) for $rideId');
    } else {
      debugPrint('⚠️ Socket not connected — location emission skipped');
    }
  }

  /// Any participant → server: ride status changed.
  void emitStatusChange({required String rideId, required String status}) {
    if (socket != null && socket!.connected) {
      socket?.emit('status_changed', {'rideId': rideId, 'status': status});
      debugPrint('📤 Status emitted: $status for $rideId');
    }
  }

  /// User → server: route distance/duration from Choose Your Ride screen.
  void emitRouteDetails({
    required String rideId,
    double? distanceKm,
    double? durationMin,
    String? distance,
    String? duration,
  }) {
    if (rideId.isEmpty || socket == null || !socket!.connected) return;
    socket?.emit('ride_route_updated', {
      'rideId': rideId,
      'distanceKm': ?distanceKm,
      'durationMin': ?durationMin,
      'distance': ?distance,
      'duration': ?duration,
    });
    debugPrint('📤 Route details emitted for $rideId');
  }

  // ── Listen ─────────────────────────────────────────────────────────────────

  /// Server → user: driver's live GPS position.
  /// Replaces any previous listener for `location_updated`.
  void onLocationUpdated(void Function(double lat, double lng) callback) {
    socket?.off('location_updated');
    socket?.on('location_updated', (data) {
      debugPrint('📥 location_updated: $data');
      if (data is Map) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) callback(lat, lng);
      }
    });
  }

  /// Server → driver: route distance/duration synced by user.
  void onRouteUpdated(void Function(Map<String, dynamic> data) callback) {
    socket?.off('ride_route_updated');
    socket?.on('ride_route_updated', (data) {
      debugPrint('📥 ride_route_updated: $data');
      if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  /// Server → driver: a new ride has been assigned.
  /// This is the real-time counterpart to the polling fallback.
  /// Payload: { rideId, pickup, destination, rideType, distance, duration, fare, driverId }
  void onNewRide(void Function(Map<String, dynamic> data) callback) {
    socket?.off('new_ride');
    socket?.off('ride_assigned');
    socket?.off('ride_request');
    // Listen on all common event names the backend might use
    for (final event in ['new_ride', 'ride_assigned', 'ride_request']) {
      socket?.on(event, (data) {
        debugPrint('📥 $event: $data');
        if (data is Map) {
          callback(Map<String, dynamic>.from(data));
        }
      });
    }
  }

  /// Remove the new_ride listener (call when driver goes offline or disposes).
  void offNewRide() {
    socket?.off('new_ride');
    socket?.off('ride_assigned');
    socket?.off('ride_request');
  }

  /// Server → all: ride status changed.
  void onStatusUpdated(void Function(String status) callback) {
    socket?.off('status_updated');
    socket?.on('status_updated', (data) {
      debugPrint('📥 status_updated: $data');
      if (data is Map) {
        final status = data['status']?.toString();
        if (status != null && status.isNotEmpty) callback(status);
      } else if (data is String && data.isNotEmpty) {
        callback(data);
      }
    });
  }

  /// Remove all listeners (call when screen disposes).
  void removeAllListeners() {
    socket?.off('location_updated');
    socket?.off('status_updated');
    socket?.off('ride_route_updated');
    socket?.off('new_ride');
    socket?.off('ride_assigned');
    socket?.off('ride_request');
  }
}
