import '../services/ride_status.dart';

/// Parsed ride payload from `GET /rides/:rideId`.
class Ride {
  final String id;
  final String status;
  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final double? driverLat;
  final double? driverLng;
  final String? userId;
  final String? driverId;
  final Map<String, String>? driver;
  final dynamic fare;
  final Map<String, dynamic> raw;

  const Ride({
    required this.id,
    required this.status,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.driverLat,
    this.driverLng,
    this.userId,
    this.driverId,
    this.driver,
    this.fare,
    required this.raw,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    final driverMap = _driverFromJson(json['driverDetails'] ?? json['driver']);

    final rawStatus = _string(
      json['status'] ??
          json['rideStatus'] ??
          json['ride_status'] ??
          json['state'] ??
          'unknown',
    );
    final effectiveStatus = RideStatus.resolveEffectiveStatus(
      json,
      RideStatus.normalize(rawStatus),
    );

    return Ride(
      id: _string(json['rideId'] ?? json['_id'] ?? json['id']),
      status: effectiveStatus,
      pickupLat: _lat(json['pickupLat']) ?? _lat(json['pickupLocation']),
      pickupLng: _lng(json['pickupLng']) ?? _lng(json['pickupLocation']),
      destinationLat:
          _lat(json['destinationLat'] ?? json['dropoffLat']) ??
          _lat(json['destinationLocation'] ?? json['dropoffLocation']),
      destinationLng:
          _lng(json['destinationLng'] ?? json['dropoffLng']) ??
          _lng(json['destinationLocation'] ?? json['dropoffLocation']),
      driverLat:
          _lat(json['driverLat'] ?? json['lat']) ??
          _lat(json['driverLocation']) ??
          (driverMap != null ? _lat(json['driver']?['lat']) : null),
      driverLng:
          _lng(json['driverLng'] ?? json['lng']) ??
          _lng(json['driverLocation']) ??
          (driverMap != null ? _lng(json['driver']?['lng']) : null),
      userId: _stringOrNull(json['userId'] ?? json['user']),
      driverId: _stringOrNull(json['driverId'] ?? json['driver']),
      driver: driverMap,
      fare: json['fare'],
      raw: json,
    );
  }

  static String _string(dynamic value) => value == null ? '' : value.toString();

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  static double? _lat(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is Map) {
      return (value['lat'] as num?)?.toDouble() ??
          (value['latitude'] as num?)?.toDouble();
    }
    return null;
  }

  static double? _lng(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is Map) {
      return (value['lng'] as num?)?.toDouble() ??
          (value['longitude'] as num?)?.toDouble();
    }
    return null;
  }

  static Map<String, String>? _driverFromJson(dynamic value) {
    if (value is! Map) return null;
    final m = Map<String, dynamic>.from(value);
    return {
      if (m['name'] != null) 'name': m['name'].toString(),
      if (m['phone'] != null) 'phone': m['phone'].toString(),
      if (m['vehicleNumber'] != null) 'vehicle': m['vehicleNumber'].toString(),
      if (m['vehicle'] != null) 'vehicle': m['vehicle'].toString(),
      if (m['rating'] != null) 'rating': m['rating'].toString(),
      if (m['eta'] != null) 'eta': m['eta'].toString(),
    };
  }

  bool get isCompleted {
    final s = status.toLowerCase();
    return s == 'completed' || s == 'ended' || s == 'finished';
  }

  bool get isDeclined {
    final s = status.toLowerCase();
    return s == 'declined' || s == 'rejected';
  }

  bool get isCancelled {
    final s = status.toLowerCase();
    return s == 'cancelled' || s == 'canceled';
  }

  bool get isPendingAssignment => RideStatus.isPending(status);

  bool get isAccepted => RideStatus.isAccepted(status);

  bool get isOngoing => RideStatus.isOngoing(status);

  bool get isActive {
    final s = status.toLowerCase();
    return s == 'accepted' ||
        s == 'assigned' ||
        s == 'started' ||
        s == 'ongoing' ||
        s == 'in_progress' ||
        s == 'near_destination';
  }

  /// Returns true when the given status string represents an active ride state
  /// (i.e. not completed, ended, cancelled or rejected).
  static bool isActiveStatus(String status) {
    final s = status.toLowerCase();
    return s.isNotEmpty &&
        s != 'completed' &&
        s != 'ended' &&
        s != 'finished' &&
        s != 'cancelled' &&
        s != 'canceled' &&
        s != 'rejected' &&
        s != 'unknown';
  }
}
