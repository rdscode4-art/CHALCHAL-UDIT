import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/ride.dart';
import '../../../core/services/active_ride_storage.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/map_utils.dart';
import '../../../core/services/ride_status.dart';
import '../../../core/services/session_service.dart';
import 'user_home_screen.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/widgets/chat_screen.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/localization/app_localizations.dart';

class UserRideProgressScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String destination;
  final String rideType;
  final Map<String, String>? driver;
  final Ride? ride;
  final Map<String, dynamic>? rideData;
  final double? distanceKm;
  final double? durationMin;

  const UserRideProgressScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.destination,
    required this.rideType,
    this.driver,
    this.ride,
    this.rideData,
    this.distanceKm,
    this.durationMin,
  });

  @override
  State<UserRideProgressScreen> createState() => _UserRideProgressScreenState();
}

class _UserRideProgressScreenState extends State<UserRideProgressScreen> {
  Timer? _pollTimer;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  Ride? _ride;
  Map<String, dynamic> _rideRaw = {};
  Map<String, String>? _driverInfo;

  // ── OTP helpers ────────────────────────────────────────────────────────────
  /// Derives a deterministic 4-digit OTP from the rideId so that user and
  /// driver always see the same value without any backend field.
  String _deriveOtp(String rideId, String salt) {
    if (rideId.isEmpty) return '----';
    final bytes = utf8.encode('$rideId:$salt');
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7FFFFFFF;
    }
    return (1000 + (hash % 9000)).toString();
  }

  String get _startOtp => _deriveOtp(widget.rideId, 'start');
  String get _completeOtp => _deriveOtp(widget.rideId, 'complete');

  String? _connectionError;
  int _currentTripStep = 0;
  String? _declineMessage;
  bool _isDeclined = false;
  int _selectedRating = 5;
  bool _submittingReview = false;
  String _userId = '';

  // Google Map controllers/vars
  GoogleMapController? _mapController;
  bool _loadingRoute = true;
  List<LatLng> _routePoints = [];
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  LatLng? _driverLatLng;
  double _driverBearing = 0.0; // heading direction of driver in degrees
  BitmapDescriptor? _driverMarkerIcon; // custom emoji marker for driver
  String _etaText = ''; // live ETA from driver to relevant waypoint
  String _headingLabel = ''; // "Heading to you" or "Heading to destination"
  Timer? _driverLocationPollTimer; // fallback: poll driver GPS from API
  String? _lastPolledDriverId; // used to detect driver id change only
  DateTime? _lastSocketUpdate; // timestamp of last socket location update
  Timer? _socketReconnectTimer; // periodically re-registers socket listeners

  // Google Maps API Key
  static const String _googleMapsApiKey =
      'AIzaSyBJ2UDH5qyj_6kwMGYvu5WKj2MlnLgRP_E';

  // Fallback locations (New Delhi)
  static const LatLng _fallbackA = LatLng(28.6139, 77.2090);
  static const LatLng _fallbackB = LatLng(28.7041, 77.1025);

  // Removed static _tripProgressSteps - will use API data
  @override
  void initState() {
    super.initState();
    ActiveRideStorage.save(widget.rideId);

    // Initialize with passed ride data if available
    if (widget.ride != null || widget.rideData != null) {
      _ride = widget.ride;
      // Merge rideData + ride.raw so fare/status are available immediately
      // before the first poll completes
      final initialRaw = <String, dynamic>{};
      if (widget.rideData != null) initialRaw.addAll(widget.rideData!);
      if (widget.ride?.raw != null) initialRaw.addAll(widget.ride!.raw);
      _rideRaw = initialRaw;
      _driverInfo = widget.driver;
      _currentTripStep = _getTripStepFromStatus(
        widget.ride?.status ?? initialRaw['status']?.toString() ?? 'pending',
      );
    }
    _applyRouteEstimates(_rideRaw);

    if (widget.rideId.isNotEmpty && !widget.rideId.startsWith('ride_')) {
      // Resolve fare from all available sources
      final fareRaw =
          _rideRaw['fare'] ?? widget.rideData?['fare'] ?? widget.ride?.fare;
      final fareNum = fareRaw is num
          ? fareRaw
          : num.tryParse(fareRaw?.toString() ?? '');
      final fareStr = (fareNum != null && fareNum > 0)
          ? fareNum.toString()
          : null;

      ApiService.syncRideRouteDetails(
        rideId: widget.rideId,
        distanceKm: widget.distanceKm,
        durationMin: widget.durationMin,
        distance: _rideRaw['distance']?.toString(),
        duration: _rideRaw['duration']?.toString(),
        fare: fareStr,
      );
      SocketService().emitRouteDetails(
        rideId: widget.rideId,
        distanceKm: widget.distanceKm,
        durationMin: widget.durationMin,
        distance: _rideRaw['distance']?.toString(),
        duration: _rideRaw['duration']?.toString(),
      );
    }

    _loadRoute();
    _startPolling();

    // Initialize socket connection and live tracking listeners
    SocketService().connect();
    SocketService().joinRide(widget.rideId);
    _registerSocketHandlers();

    // Load user ID for chat
    SessionService.getUserId().then((id) {
      if (mounted && id != null && id.isNotEmpty) {
        setState(() => _userId = id);
      }
    });

    // Eagerly seed driver location from the initial ride data/model
    // so the map shows something while socket/API fetches happen
    _seedDriverLocationFromRideData();

    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      final data = message.data;
      final event = data['event'];
      final msgRideId = data['rideId'];
      if (msgRideId == widget.rideId && event == 'ride_rejected') {
        debugPrint('🚫 [FCM] ride_rejected received for $msgRideId! Reverting to bidding screen.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver rejected the ride. Reverting to bidding screen...'),
            backgroundColor: AppColors.accentRed,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _driverLocationPollTimer?.cancel();
    _driverLocationPollTimer = null;
    _socketReconnectTimer?.cancel();
    _socketReconnectTimer = null;
  }

  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollRideStatus();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollRideStatus(),
    );
    // Fallback: poll driver GPS from API every 5s when socket is silent
    _driverLocationPollTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshDriverLocationFromApi(),
    );
    // Re-register socket listeners every 15s in case the connection dropped
    _socketReconnectTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _reRegisterSocketListeners(),
    );
  }

  /// Re-registers socket listeners and reconnects if needed.
  /// Called on a timer so a dropped socket is recovered without a full restart.
  void _reRegisterSocketListeners() {
    if (!mounted) return;
    final socket = SocketService();
    if (!socket.isConnected) {
      debugPrint('🔄 [SOCKET] Reconnecting...');
      socket.connect();
    }
    socket.joinRide(widget.rideId);
    _registerSocketHandlers();
  }

  void _registerSocketHandlers() {
    SocketService().onLocationUpdated((lat, lng) {
      debugPrint('📍 [SOCKET] Location update: $lat, $lng');
      if (!mounted) return;
      final newPos = LatLng(lat, lng);
      setState(() {
        if (_driverLatLng != null) {
          _driverBearing = MapUtils.calculateBearing(_driverLatLng!, newPos);
        }
        _driverLatLng = newPos;
        _lastSocketUpdate = DateTime.now();
        _updateEtaAndHeading(newPos);
      });
      // Smoothly follow the driver and rotate map to heading direction
      _animateCameraToDriver(newPos);
    });

    SocketService().onStatusUpdated((status) {
      debugPrint('🔔 [SOCKET] Status update: $status');
      if (!mounted) return;
      _pollRideStatus();
    });
  }

  /// Animates the camera to follow the driver and rotates the map to face
  /// the direction of travel — gives the user a directional view of the driver.
  void _animateCameraToDriver(LatLng driverPos) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: driverPos,
          zoom: 16.0,
          // Rotate the map so the driver's heading is always "up"
          bearing: _driverBearing,
          tilt: 0.0, // keep flat on user side for readability
        ),
      ),
    );
  }

  /// Seeds driver location from data already available in the ride model/raw,
  Future<void> _seedDriverLocationFromRideData() async {
    // Try from Ride model fields first
    double? lat = _ride?.driverLat;
    double? lng = _ride?.driverLng;

    // Try from raw ride payload
    if (lat == null || lng == null || lat == 0.0 || lng == 0.0) {
      lat = _extractDouble(_rideRaw, [
        'driverLat',
        'driverLatitude',
        'lat',
        'driver_lat',
      ]);
      lng = _extractDouble(_rideRaw, [
        'driverLng',
        'driverLongitude',
        'lng',
        'driver_lng',
      ]);
    }

    // Try from nested driver object
    if ((lat == null || lat == 0.0) && _rideRaw['driver'] is Map) {
      final d = _rideRaw['driver'] as Map;
      lat = _extractDouble(d, ['lat', 'latitude', 'currentLat']);
      lng = _extractDouble(d, ['lng', 'longitude', 'currentLng']);
    }

    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      final pos = LatLng(lat, lng);
      final vType = widget.rideType.isNotEmpty
          ? widget.rideType
          : (_rideRaw['rideType']?.toString() ??
                _rideRaw['vehicleType']?.toString() ??
                'auto');
      final icon = await MapUtils.get3DVehicleMarkerForType(vType);
      if (!mounted) return;
      setState(() {
        _driverLatLng = pos;
        _driverMarkerIcon = icon;
        _updateEtaAndHeading(pos);
      });
      debugPrint('📍 [DRIVER_LOC] Seeded from ride data: $lat, $lng');
      return;
    }

    // No location in ride data — fetch from driver profile API immediately
    final driverId = _resolveDriverId();
    if (driverId.isNotEmpty) {
      await _fetchInitialDriverLocation(driverId);
    }
  }

  void _updateEtaAndHeading(LatLng driverPos) {
    final status = RideStatus.normalize(_rideRaw['status']?.toString() ?? '');
    final isOngoing = RideStatus.isOngoing(status);
    final etaTarget = isOngoing ? _destLatLng : _pickupLatLng;
    if (etaTarget != null) {
      _etaText = MapUtils.etaString(driverPos, etaTarget);
    }
    _headingLabel = isOngoing ? 'Heading to destination' : 'Heading to you';
  }

  /// Fetches the driver's current lat/lng from their profile API.
  /// Used as an initial seed and as a fallback when socket is silent.
  Future<void> _fetchInitialDriverLocation(String driverId) async {
    if (driverId.isEmpty) return;
    // Update _lastPolledDriverId so we know which driver we're tracking
    _lastPolledDriverId = driverId;
    try {
      final res = await ApiService.getDriverById(driverId);
      if (!mounted || !res.success) return;

      // Try all common location field names the backend might use
      final data = res.data;
      final dynamic driverData = data['driver'] is Map ? data['driver'] : data;
      final lat = _extractDouble(driverData, ['lat', 'latitude', 'currentLat']);
      final lng = _extractDouble(driverData, [
        'lng',
        'longitude',
        'currentLng',
      ]);

      if (lat == null || lng == null || lat == 0.0 || lng == 0.0) {
        debugPrint(
          '📍 [DRIVER_LOC] No valid location in API response for $driverId',
        );
        return;
      }

      final pos = LatLng(lat, lng);
      if (!mounted) return;

      // Pre-load vehicle marker icon
      final vType = widget.rideType.isNotEmpty
          ? widget.rideType
          : (_rideRaw['rideType']?.toString() ??
                _rideRaw['vehicleType']?.toString() ??
                'auto');
      final icon = await MapUtils.get3DVehicleMarkerForType(vType);
      if (!mounted) return;

      setState(() {
        _driverLatLng = pos;
        _driverMarkerIcon = icon;
        _updateEtaAndHeading(pos);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
      debugPrint('📍 [DRIVER_LOC] Initial position from API: $lat, $lng');
    } catch (e) {
      debugPrint('❌ [DRIVER_LOC] Failed to fetch driver location: $e');
    }
  }

  /// Extracts a non-null, non-zero double from [map] trying keys in order.
  double? _extractDouble(dynamic map, List<String> keys) {
    if (map is! Map) return null;
    for (final key in keys) {
      final v = map[key];
      if (v == null) continue;
      final d = v is num ? v.toDouble() : double.tryParse(v.toString());
      if (d != null && d != 0.0) return d;
    }
    return null;
  }

  /// Periodically polls driver GPS from API as a socket fallback.
  /// Only calls the API when socket has been silent for > 10 seconds.
  Future<void> _refreshDriverLocationFromApi() async {
    if (!mounted) return;

    // Skip if socket delivered a fresh update within the last 10 seconds
    final socketAge = _lastSocketUpdate != null
        ? DateTime.now().difference(_lastSocketUpdate!).inSeconds
        : 9999;
    if (socketAge < 10) return;

    // Resolve driver ID from all possible fields in the ride payload
    final driverId = _resolveDriverId();
    if (driverId.isEmpty) return;

    try {
      final res = await ApiService.getDriverById(driverId);
      if (!mounted || !res.success) return;

      final data = res.data;
      final dynamic driverData = data['driver'] is Map ? data['driver'] : data;
      final lat = _extractDouble(driverData, ['lat', 'latitude', 'currentLat']);
      final lng = _extractDouble(driverData, [
        'lng',
        'longitude',
        'currentLng',
      ]);

      if (lat == null || lng == null || lat == 0.0 || lng == 0.0) return;

      final pos = LatLng(lat, lng);
      if (!mounted) return;
      setState(() {
        if (_driverLatLng != null) {
          _driverBearing = MapUtils.calculateBearing(_driverLatLng!, pos);
        }
        _driverLatLng = pos;
        _updateEtaAndHeading(pos);
      });
      _animateCameraToDriver(pos);
      debugPrint('📍 [DRIVER_LOC_POLL] API fallback: $lat, $lng');
    } catch (_) {}
  }

  /// Resolves the driver ID from all possible fields in the current ride data.
  String _resolveDriverId() {
    // Direct fields
    for (final key in ['driverId', 'assignedDriverId', 'driver_id']) {
      final v = _rideRaw[key]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    // Nested driver object
    final driverObj = _rideRaw['driver'];
    if (driverObj is Map) {
      for (final key in ['_id', 'id', 'driverId']) {
        final v = driverObj[key]?.toString().trim() ?? '';
        if (v.isNotEmpty && v != 'null') return v;
      }
    }
    // From ride model
    return _ride?.driverId ?? _lastPolledDriverId ?? '';
  }

  Map<String, String>? _driverFromMap(Map<String, dynamic> m) {
    final driver = m['driver'];
    if (driver is Map) {
      final d = Map<String, dynamic>.from(driver);
      return {
        if (d['name'] != null) 'name': d['name'].toString(),
        if (d['phone'] != null) 'phone': d['phone'].toString(),
        if (d['vehicleNumber'] != null)
          'vehicle': d['vehicleNumber'].toString(),
        if (d['vehicle'] != null) 'vehicle': d['vehicle'].toString(),
        if (d['vehicleType'] != null)
          'vehicleType': d['vehicleType'].toString(),
      };
    }
    if (m['driverName'] != null) {
      return {
        'name': m['driverName'].toString(),
        if (m['driverPhone'] != null) 'phone': m['driverPhone'].toString(),
      };
    }
    return widget.driver;
  }

  void _applyRouteEstimates(Map<String, dynamic> target) {
    final fromWidgetKm = widget.distanceKm;
    final fromWidgetMin = widget.durationMin;
    final fromDataKm = target['distanceKm'] ?? target['distance_km'];
    final fromDataMin =
        target['durationMin'] ??
        target['duration_min'] ??
        target['durationMins'];

    double? km = fromWidgetKm;
    if ((km == null || km <= 0) && _isValidDistanceValue(fromDataKm)) {
      km = _parseDistanceKm(fromDataKm);
    }
    if (km != null && km > 0) {
      target['distanceKm'] = km;
      target['distance'] = '${km.toStringAsFixed(1)} km';
    }

    double? mins = fromWidgetMin;
    if ((mins == null || mins <= 0) && _isValidDurationValue(fromDataMin)) {
      mins = _parseDurationMin(fromDataMin);
    }
    if (mins != null && mins > 0) {
      target['durationMin'] = mins;
      target['duration'] = '${mins.round()} mins';
    }
  }

  double? _parseDistanceKm(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value.toDouble() : null;
    return double.tryParse(value.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  double? _parseDurationMin(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value.toDouble() : null;
    return double.tryParse(value.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  bool _isValidDistanceValue(dynamic value) {
    final km = _parseDistanceKm(value);
    return km != null && km > 0;
  }

  bool _isValidDurationValue(dynamic value) {
    final mins = _parseDurationMin(value);
    return mins != null && mins > 0;
  }

  Map<String, dynamic> _mergePollRideData(Map<String, dynamic> apiData) {
    final merged = <String, dynamic>{..._rideRaw, ...apiData};

    for (final key in ['distance', 'distanceKm', 'distance_km']) {
      if (!_isValidDistanceValue(merged[key]) &&
          _isValidDistanceValue(_rideRaw[key])) {
        merged[key] = _rideRaw[key];
      }
    }
    for (final key in [
      'duration',
      'durationMin',
      'duration_min',
      'durationMins',
    ]) {
      if (!_isValidDurationValue(merged[key]) &&
          _isValidDurationValue(_rideRaw[key])) {
        merged[key] = _rideRaw[key];
      }
    }

    // Protect fare: never overwrite a positive fare with zero/null from polling.
    // The backend may reset fare to 0 on /rides/start — we keep the last good value.
    for (final key in ['fare', 'finalFare', 'price', 'estimatedFare']) {
      final existing = _rideRaw[key];
      final updated = merged[key];
      final existingNum = existing is num
          ? existing
          : num.tryParse(existing?.toString() ?? '');
      final updatedNum = updated is num
          ? updated
          : num.tryParse(updated?.toString() ?? '');
      if ((existingNum != null && existingNum > 0) &&
          (updatedNum == null || updatedNum <= 0)) {
        merged[key] = existing; // restore previous valid value
      }
    }

    // Also pull fare from widget if _rideRaw still has nothing
    if ((merged['fare'] == null ||
            num.tryParse(merged['fare'].toString()) == null ||
            (num.tryParse(merged['fare'].toString()) ?? 0) <= 0) &&
        widget.rideData?['fare'] != null) {
      final widgetFare = widget.rideData!['fare'];
      final widgetFareNum = widgetFare is num
          ? widgetFare
          : num.tryParse(widgetFare.toString());
      if (widgetFareNum != null && widgetFareNum > 0) {
        merged['fare'] = widgetFare;
        merged['finalFare'] = widgetFare;
        merged['price'] = widgetFare;
      }
    }

    _applyRouteEstimates(merged);
    return merged;
  }

  String _resolveDistanceDisplay() {
    if (widget.distanceKm != null && widget.distanceKm! > 0) {
      return '${widget.distanceKm!.toStringAsFixed(1)} km';
    }

    for (final key in ['distance', 'distanceKm', 'distance_km']) {
      final value = _rideRaw[key];
      if (!_isValidDistanceValue(value)) continue;
      if (key == 'distance') {
        final s = value.toString().trim();
        if (s.toLowerCase().contains('km')) return s;
      }
      final km = _parseDistanceKm(value);
      if (km != null && km > 0) {
        return '${km.toStringAsFixed(1)} km';
      }
    }
    return '—';
  }

  String _resolveDurationDisplay() {
    if (widget.durationMin != null && widget.durationMin! > 0) {
      return '${widget.durationMin!.round()} ${context.tr('mins')}';
    }

    for (final key in [
      'duration',
      'durationMin',
      'duration_min',
      'durationMins',
    ]) {
      final value = _rideRaw[key];
      if (!_isValidDurationValue(value)) continue;
      if (key == 'duration') {
        final s = value.toString().trim();
        if (s.toLowerCase().contains('min')) return s;
      }
      final mins = _parseDurationMin(value);
      if (mins != null && mins > 0) {
        return '${mins.round()} ${context.tr('mins')}';
      }
    }
    return '—';
  }

  Future<void> _pollRideStatus() async {
    if (!mounted || widget.rideId.isEmpty) return;

    try {
      final res = await ApiService.getRide(widget.rideId);
      debugPrint(
        '🔄 [POLL] rideId=${widget.rideId} success=${res.success} statusCode=${res.statusCode}',
      );
      if (!mounted) return;

      if (res.statusCode == 404) {
        _stopPolling();
        await ActiveRideStorage.clear();
        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
        return;
      }

      if (!res.success) {
        debugPrint('❌ [POLL] API error: ${res.errorMessage}');
        setState(() {
          _connectionError = res.statusCode != null && res.statusCode! >= 500
              ? 'Connection error, retrying...'
              : (res.errorMessage ?? 'No internet connection');
        });
        return;
      }

      // Merge raw API data — preserve all original fields from the API
      // response (completedAt, distanceKm, fare, notes, etc.) then
      // overlay the normalized fields from ApiService.
      final raw = _mergePollRideData(Map<String, dynamic>.from(res.data));

      final status = RideStatus.resolveEffectiveStatus(
        raw,
        raw['status']?.toString() ?? '',
      );
      raw['status'] = status;

      debugPrint('🔄 [POLL] resolved status=$status');
      debugPrint(
        '🔄 [POLL] fare=${raw['fare']} distance=${raw['distance']} completedAt=${raw['completedAt']}',
      );
      debugPrint(
        '🔄 [POLL] tripStep=${_getTripStepFromStatus(status)} isAccepted=${RideStatus.isAccepted(status)} isOngoing=${RideStatus.isOngoing(status)} isCompleted=${RideStatus.isCompleted(status)}',
      );

      final ride = Ride.fromJson(raw);
      final driver = _driverFromMap(raw);

      // Check if ride was declined (explicit declined status)
      final isDeclined = RideStatus.isDeclined(status);

      // Detect driver-initiated cancel:
      // - Backend sets cancelled when driver calls POST /rides/cancel with driverId
      // - User-initiated cancel sets cancelledBy='user'
      // So: cancelled + cancelledBy != 'user' → driver declined
      final isCancelled = RideStatus.isCancelled(status);
      final cancelledBy = raw['cancelledBy']?.toString().toLowerCase() ?? '';
      final isDriverDecline = isCancelled && cancelledBy != 'user';

      final effectivelyDeclined = isDeclined || isDriverDecline;

      final declineReason = 'Driver declined your ride. Please book again.';

      // Check if ride is completed
      final isCompleted = RideStatus.isCompleted(status);

      if (mounted) {
        final oldStatus = RideStatus.normalize(
          _rideRaw['status']?.toString() ?? '',
        );
        final newStatus = RideStatus.normalize(status);

        // If the ride was previously accepted/assigned but the backend reverted it to pending (driver rejected),
        // we should pop back to the DriversListScreen (bidding screen).
        if (oldStatus.isNotEmpty &&
            oldStatus != 'pending' &&
            oldStatus != 'requested' &&
            newStatus == 'pending') {
          debugPrint('🚫 Driver rejected/unassigned! Reverting to bidding screen.');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Driver rejected the ride. Reverting to bidding screen...'),
              backgroundColor: AppColors.accentRed,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
          return;
        }

        setState(() {
          _ride = ride;
          _rideRaw = raw;
          _driverInfo = driver ?? _driverInfo;
          _connectionError = null;
          _isDeclined = effectivelyDeclined;
          _declineMessage = effectivelyDeclined ? declineReason : null;
          _currentTripStep = _getTripStepFromStatus(status);
        });
        if (oldStatus != newStatus) {
          _loadRoute();
        }

        // Fetch/refresh driver location when ride is accepted or ongoing
        if (RideStatus.isAccepted(status) || RideStatus.isOngoing(status)) {
          final driverId = _resolveDriverId();
          if (driverId.isNotEmpty) {
            // Always update tracking ID; only hit API if no socket update recently
            _lastPolledDriverId = driverId;
            if (_driverLatLng == null) {
              _fetchInitialDriverLocation(driverId);
            }
          }
        }
      }

      if (effectivelyDeclined || isCompleted || isCancelled) {
        _stopPolling();
        if (isCompleted || (isCancelled && !effectivelyDeclined)) {
          await ActiveRideStorage.clear();
        }
        // For driver decline, clear active ride too so user can rebook
        if (effectivelyDeclined) {
          await ActiveRideStorage.clear();
        }
      }
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('❌ [USER_PROGRESS] poll error: $e\n$st');
      setState(() => _connectionError = 'No internet connection');
    }
  }

  Future<void> _bookAnotherRide() async {
    await ActiveRideStorage.clear();
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  bool _isDriverMatchingRideType() {
    // If we have any driver details, always show the driver card so the user can communicate.
    if (_driverInfo != null && (_driverInfo!['name']?.isNotEmpty == true)) {
      return true;
    }
    final status = RideStatus.normalize(
      _rideRaw['status']?.toString() ?? _ride?.status ?? 'pending',
    );
    return RideStatus.isAccepted(status) || RideStatus.isOngoing(status);
  }

  int _getTripStepFromStatus(String status) {
    // status here is already the output of resolveEffectiveStatus — it may be
    // a canonical value ('ongoing', 'accepted') or a raw backend value
    // ('started', 'in_progress', etc.). Run it through all checks.
    if (RideStatus.isCompleted(status)) return 3;
    if (RideStatus.isOngoing(status)) return 2;
    if (RideStatus.isAccepted(status)) return 1;
    if (RideStatus.isPending(status)) return 0;
    // Fallback: keep current step so timeline doesn't jump backwards
    return _currentTripStep;
  }

  // ── OTP Card ───────────────────────────────────────────────────────────────
  Widget _buildOtpCard(String status, Color card, Color text, Color sub) {
    final bool showStart = RideStatus.isAccepted(status);
    final bool showComplete = RideStatus.isOngoing(status);
    if (!showStart && !showComplete) return const SizedBox.shrink();

    final String otp = showStart ? _startOtp : _completeOtp;
    final String label = showStart ? 'Start Ride OTP' : 'Complete Ride OTP';
    final String hint = showStart
        ? 'Show this OTP to your driver to start the ride'
        : 'Show this OTP to your driver to complete the ride';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentStrong.withValues(alpha: 0.92),
            AppColors.secondary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentStrong.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: otp.split('').map((digit) {
              return Container(
                width: 54,
                height: 64,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripProgressTimeline(
    Color card,
    Color text,
    Color sub,
    Color green,
    Color red,
  ) {
    // Dynamic timeline based on API status
    final timelineSteps = [
      {'title': 'Ride Assigned', 'subtitle': 'Driver has been notified'},
      {'title': 'Driver Accepted', 'subtitle': 'Driver will arrive soon'},
      {'title': 'Trip Started', 'subtitle': 'Driver is on the way'},
      {'title': 'Completed', 'subtitle': 'Trip finished. Thank you!'},
    ];

    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Trip Progress',
            style: AppTextStyles.heading.copyWith(
              fontSize: 16,
              color: text,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: List.generate(timelineSteps.length, (index) {
              final step = timelineSteps[index];
              final completed = index < _currentTripStep;
              final active = index == _currentTripStep;
              final isLast = index == timelineSteps.length - 1;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dot + connector
                      Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: (completed || active)
                                  ? green
                                  : card.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: active
                                  ? Border.all(color: green, width: 2)
                                  : null,
                            ),
                            child: completed
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 12,
                                  )
                                : null,
                          ),
                          if (!isLast)
                            Container(
                              width: 2,
                              height: 54,
                              margin: const EdgeInsets.only(top: 4),
                              color: completed
                                  ? green
                                  : sub.withValues(alpha: 0.2),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      // Step text
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step['title']!,
                                style: AppTextStyles.cardTitle.copyWith(
                                  fontSize: 13,
                                  color: (completed || active) ? text : sub,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                step['subtitle']!,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 12,
                                  color: sub.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast) const SizedBox(height: 12),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStar(Color sub, int value) {
    final selected = value <= _selectedRating;
    return GestureDetector(
      onTap: () => setState(() => _selectedRating = value),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        scale: selected ? 1.15 : 1.0,
        child: Icon(
          selected ? Icons.star : Icons.star_border,
          color: selected ? AppColors.accentYellow : sub,
          size: 34,
        ),
      ),
    );
  }

  Widget _buildReviewSection(Color card, Color text, Color sub) {
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rate your driver',
            style: AppTextStyles.heading.copyWith(
              fontSize: 16,
              color: text,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'How was your ride experience?',
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              color: sub.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) => _buildRatingStar(sub, i + 1)),
          ),
          const SizedBox(height: 20),
          CustomButton(
            label: _submittingReview ? 'Submitting…' : 'Submit Rating',
            color: AppColors.accentStrong,
            onPressed: _submittingReview
                ? () {}
                : () async {
                    setState(() => _submittingReview = true);
                    final res = await ApiService.rateRide(
                      rideId: widget.rideId,
                      rating: _selectedRating,
                      ratingComment: '',
                    );
                    if (!mounted) return;
                    setState(() => _submittingReview = false);

                    if (res.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('ratingSuccess')),
                          backgroundColor: AppColors.secondary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      // Clear active ride storage and go back to homepage
                      await ActiveRideStorage.clear();
                      if (mounted) {
                        Navigator.popUntil(context, (r) => r.isFirst);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to submit rating: ${res.errorMessage}',
                          ),
                          backgroundColor: AppColors.accentRed,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }

  // ✅ CRITICAL FIX #2: Protect back button during active ride
  Future<bool> _onWillPop() async {
    if (_ride != null &&
        !_ride!.isCompleted &&
        !RideStatus.isDeclined(_ride!.status)) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text(context.tr('activeRide')),
              content: Text(context.tr('exitConfirm')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('stay')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.tr('exit')),
                ),
              ],
            ),
          ) ??
          false;
      
      if (confirmed && mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const UserHomeScreen()),
          (r) => false,
        );
      }
      return false; // Prevent default single-route pop
    }

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const UserHomeScreen()),
        (r) => false,
      );
    }
    return false;
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _stopPolling();
    SocketService().removeAllListeners();
    SocketService().leaveRide(widget.rideId);
    super.dispose();
  }

  Future<void> _loadRoute() async {
    if (!mounted) return;
    setState(() => _loadingRoute = true);

    final pickup =
        _rideRaw['pickupLocation']?.toString() ??
        _rideRaw['pickup']?.toString() ??
        widget.pickup;
    final dropoff =
        _rideRaw['dropoffLocation']?.toString() ??
        _rideRaw['destination']?.toString() ??
        _rideRaw['destinationLocation']?.toString() ??
        widget.destination;

    _pickupLatLng = await MapUtils.geocode(pickup) ?? _fallbackA;
    _destLatLng = await MapUtils.geocode(dropoff) ?? _fallbackB;

    // Update ETA and heading now that we have geocoded endpoints
    if (_driverLatLng != null) _updateEtaAndHeading(_driverLatLng!);

    final status = RideStatus.normalize(
      _rideRaw['status']?.toString() ?? _ride?.status ?? 'pending',
    );

    final bool driverKnown = _driverLatLng != null;

    LatLng originPoint;
    LatLng destPoint;

    if (RideStatus.isOngoing(status) || RideStatus.isCompleted(status)) {
      originPoint = _driverLatLng ?? _pickupLatLng ?? _fallbackA;
      destPoint = _destLatLng ?? _fallbackB;
    } else {
      // Pre-trip: route from driver (if known) to pickup
      originPoint = _driverLatLng ?? _pickupLatLng ?? _fallbackA;
      destPoint = _pickupLatLng ?? _fallbackA;
    }

    // Only draw the route when origin ≠ destination (avoids a useless API call)
    if (originPoint.latitude != destPoint.latitude ||
        originPoint.longitude != destPoint.longitude) {
      final result = await MapUtils.getDirections(
        origin: originPoint,
        destination: destPoint,
      );
      _routePoints = result.points;
    } else {
      _routePoints = [];
    }

    // Pre-load vehicle 3D marker
    final vType = widget.rideType.isNotEmpty
        ? widget.rideType
        : (_rideRaw['rideType']?.toString() ??
              _rideRaw['vehicleType']?.toString() ??
              'auto');
    _driverMarkerIcon = await MapUtils.get3DVehicleMarkerForType(vType);

    if (mounted) {
      setState(() => _loadingRoute = false);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _fitMapBounds();
      });

      // If the driver location wasn't known yet when route loaded,
      // schedule a re-load once the first driver location arrives.
      if (!driverKnown) {
        _scheduleRouteReloadOnDriverLocation();
      }
    }
  }

  /// Waits for `_driverLatLng` to become non-null then reloads the route once.
  void _scheduleRouteReloadOnDriverLocation() {
    const maxWait = Duration(seconds: 30);
    const check = Duration(seconds: 2);
    var elapsed = Duration.zero;
    Timer? waiter;
    waiter = Timer.periodic(check, (_) {
      elapsed += check;
      if (_driverLatLng != null) {
        waiter?.cancel();
        if (mounted) _loadRoute();
      } else if (elapsed >= maxWait) {
        waiter?.cancel();
      }
    });
  }

  void _fitMapBounds() {
    if (_mapController == null) return;
    final allPoints = [
      if (_routePoints.isNotEmpty)
        ..._routePoints
      else ...[
        ?_pickupLatLng,
        ?_destLatLng,
      ],
      ?_driverLatLng,
    ];
    MapUtils.fitBounds(
      _mapController!,
      allPoints.isEmpty ? [_fallbackA] : allPoints,
      padding: 60,
    );
  }

  Widget _buildMap(Color card, Color text, Color sub, bool isDark) {
    final pickup =
        _rideRaw['pickupLocation']?.toString() ??
        _rideRaw['pickup']?.toString() ??
        widget.pickup;
    final dropoff =
        _rideRaw['dropoffLocation']?.toString() ??
        _rideRaw['destination']?.toString() ??
        _rideRaw['destinationLocation']?.toString() ??
        widget.destination;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Map header with ETA ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.map_outlined,
                  color: AppColors.secondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live Tracking',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: text,
                    ),
                  ),
                ),
                // Live heading + ETA chip
                if (_driverLatLng != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.navigation_rounded,
                          color: AppColors.secondary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _headingLabel.isNotEmpty
                              ? _headingLabel
                              : 'On the way',
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_etaText.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 1,
                            height: 12,
                            color: AppColors.secondary.withAlpha(80),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.access_time_rounded,
                            color: AppColors.secondary,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _etaText,
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // ── Map ─────────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: SizedBox(
              height: 260,
              child: _loadingRoute
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.secondary,
                      ),
                    )
                  : Stack(
                      children: [
                        GoogleMap(
                          onMapCreated: (GoogleMapController controller) {
                            _mapController = controller;
                            _fitMapBounds();
                          },
                          initialCameraPosition: CameraPosition(
                            target:
                                _driverLatLng ?? _pickupLatLng ?? _fallbackA,
                            zoom: 14,
                          ),
                          mapType: MapType.normal,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          polylines: _routePoints.isNotEmpty
                              ? {
                                  Polyline(
                                    polylineId: const PolylineId('route'),
                                    points: _routePoints,
                                    color: AppColors.secondary,
                                    width: 5,
                                    geodesic: true,
                                    startCap: Cap.roundCap,
                                    endCap: Cap.roundCap,
                                    jointType: JointType.round,
                                  ),
                                }
                              : {},
                          markers: {
                            if (_pickupLatLng != null)
                              Marker(
                                markerId: const MarkerId('pickup'),
                                position: _pickupLatLng!,
                                infoWindow: InfoWindow(
                                  title: '📍 Your Pickup',
                                  snippet: pickup,
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueBlue,
                                ),
                              ),
                            if (_destLatLng != null)
                              Marker(
                                markerId: const MarkerId('destination'),
                                position: _destLatLng!,
                                infoWindow: InfoWindow(
                                  title: '🏁 Destination',
                                  snippet: dropoff,
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueRed,
                                ),
                              ),
                            if (_driverLatLng != null)
                              Marker(
                                markerId: const MarkerId('driver'),
                                position: _driverLatLng!,
                                rotation: _driverBearing,
                                flat: true,
                                anchor: const Offset(0.5, 0.5),
                                infoWindow: InfoWindow(
                                  title:
                                      '🚗 ${_driverInfo?['name'] ?? 'Driver'}',
                                  snippet: _headingLabel.isNotEmpty
                                      ? '$_headingLabel${_etaText.isNotEmpty ? ' • ETA: $_etaText' : ''}'
                                      : (_etaText.isNotEmpty
                                            ? 'ETA: $_etaText'
                                            : 'On the way'),
                                ),
                                icon:
                                    _driverMarkerIcon ??
                                    BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueYellow,
                                    ),
                              ),
                          },
                        ),
                        // ── Centre-on-driver button ──────────────────────
                        if (_driverLatLng != null)
                          Positioned(
                            bottom: 14,
                            right: 14,
                            child: GestureDetector(
                              onTap: () {
                                if (_mapController != null &&
                                    _driverLatLng != null) {
                                  // Snap to driver with heading rotation
                                  _animateCameraToDriver(_driverLatLng!);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(230),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(30),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: AppColors.secondary,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        // ── Google Map Redirection / Navigation Button ──────────
                        Positioned(
                          top: 14,
                          right: 14,
                          child: GestureDetector(
                            onTap: () async {
                              final pickup =
                                  _rideRaw['pickupLocation']?.toString() ??
                                  _rideRaw['pickup']?.toString() ??
                                  widget.pickup;
                              final dropoff =
                                  _rideRaw['dropoffLocation']?.toString() ??
                                  _rideRaw['destination']?.toString() ??
                                  widget.destination;

                              final query = Uri.encodeComponent(dropoff);
                              final origin = Uri.encodeComponent(pickup);
                              final url =
                                  'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$query&travelmode=driving';
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not launch Google Maps',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(230),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(30),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.map_rounded,
                                color: AppColors.secondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // ── Fit-all button (north-up overview) ──────────
                        Positioned(
                          bottom: 14,
                          left: 14,
                          child: GestureDetector(
                            onTap: () {
                              // Reset bearing to north-up then fit all points
                              _mapController?.animateCamera(
                                CameraUpdate.newCameraPosition(
                                  const CameraPosition(
                                    target: LatLng(0, 0),
                                    bearing: 0,
                                    tilt: 0,
                                    zoom: 14,
                                  ),
                                ),
                              );
                              Future.delayed(
                                const Duration(milliseconds: 200),
                                _fitMapBounds,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(230),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(30),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.fit_screen,
                                color: AppColors.accentStrong,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // ── Heading label badge (bottom centre) ──────────
                        if (_driverLatLng != null && _headingLabel.isNotEmpty)
                          Positioned(
                            bottom: 14,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(160),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Rotating arrow that shows heading direction
                                    Transform.rotate(
                                      // bearing is clockwise from north;
                                      // Icons.navigation points up (north) by default
                                      angle: _driverBearing * 3.14159265 / 180,
                                      child: const Icon(
                                        Icons.navigation,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _headingLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_etaText.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '• $_etaText',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(200),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final card = isDark ? AppColors.darkSurface : AppColors.surface;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.6)
        : AppColors.textGrey;

    // Use _rideRaw['status'] directly — it is set to the resolved status in
    // _pollRideStatus before setState is called, so it's always up to date.
    final status = RideStatus.normalize(
      _rideRaw['status']?.toString() ?? _ride?.status ?? 'pending',
    );
    final driver = _driverInfo ?? widget.driver;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text(
            'Your trip',
            style: AppTextStyles.heading.copyWith(fontSize: 18, color: text),
          ),
          backgroundColor: card,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).padding.bottom + 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_connectionError != null) ...[
                  Text(
                    _connectionError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.accentYellow),
                  ),
                  const SizedBox(height: 12),
                ],
                _statusHeader(status, card, text, sub),
                if (RideStatus.isCompleted(status)) ...[
                  const SizedBox(height: 16),
                  _buildReviewSection(card, text, sub),
                ],
              _buildOtpCard(status, card, text, sub),
              const SizedBox(height: 20),
              _buildMap(card, text, sub, isDark),
              if (driver != null && _isDriverMatchingRideType())
                _driverCard(driver, card, text, sub),
              const SizedBox(height: 16),
              _locationCard(card, text, sub),
              const SizedBox(height: 20),
              // Show decline message if declined
              if (_isDeclined && _declineMessage != null) ...[
                GlassCard(
                  borderRadius: BorderRadius.circular(18),
                  color: AppColors.accentRed.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.accentRed.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cancel_rounded,
                        color: AppColors.accentRed,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ride Declined',
                              style: AppTextStyles.heading.copyWith(
                                fontSize: 14,
                                color: AppColors.accentRed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _declineMessage!,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CustomButton(
                  label: 'Book Another Ride',
                  color: AppColors.accentStrong,
                  onPressed: _bookAnotherRide,
                ),
                const SizedBox(height: 20),
              ] else ...[
                _buildTripProgressTimeline(
                  card,
                  text,
                  sub,
                  AppColors.accentStrong,
                  AppColors.accentRed,
                ),
                const SizedBox(height: 16),
                if (RideStatus.isCompleted(status)) ...[
                  const SizedBox(height: 16),
                  _summaryCard(card, text, sub),
                ],
                if (RideStatus.isPending(status) || RideStatus.isAccepted(status)) ...[
                  const SizedBox(height: 20),
                  CustomButton(
                    label: context.tr('cancelRideBtn'),
                    color: AppColors.accentRed,
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(context.tr('cancelRideQuestion')),
                          content: Text(context.tr('cancelRideConfirm')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(context.tr('no')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.accentRed,
                              ),
                              child: Text(context.tr('yesCancel')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        if (widget.rideId.isNotEmpty) {
                          await ApiService.cancelRideByUser(
                            rideId: widget.rideId,
                            cancelledBy: 'user',
                          );
                        }
                        await ActiveRideStorage.clear();
                        if (mounted) {
                          Navigator.popUntil(context, (r) => r.isFirst);
                        }
                      }
                    },
                  ),
                ],
              ],
              if (RideStatus.isCancelled(status) && !_isDeclined) ...[
                const SizedBox(height: 24),
                CustomButton(
                  label: 'Book Another Ride',
                  color: AppColors.accentStrong,
                  onPressed: _bookAnotherRide,
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _statusHeader(String status, Color card, Color text, Color sub) {
    String title;
    String subtitle;
    IconData icon;
    Color color;

    if (RideStatus.isDeclined(status)) {
      title = 'Driver Declined';
      subtitle = 'Your ride was declined by the driver';
      icon = Icons.cancel_rounded;
      color = AppColors.accentRed;
    } else if (RideStatus.isAccepted(status)) {
      final eta = _rideRaw['eta']?.toString() ?? _driverInfo?['eta'] ?? '—';
      title = 'Driver is on the way';
      subtitle = 'ETA: $eta  •  Show OTP to driver to start ride';
      icon = Icons.directions_car_outlined;
      color = AppColors.accentStrong;
    } else if (RideStatus.isOngoing(status)) {
      final distance = _rideRaw['distance']?.toString() ?? '—';
      title = 'Ride in progress';
      subtitle = 'Distance: $distance  •  Show OTP to driver to complete';
      icon = Icons.route;
      color = AppColors.accentStrong;
    } else if (RideStatus.isCompleted(status)) {
      final rawFare = _rideRaw['fare'];
      final fareNum = rawFare is num
          ? rawFare
          : num.tryParse(rawFare?.toString() ?? '');
      final fare = (fareNum != null && fareNum > 0)
          ? '₹${fareNum.toStringAsFixed(fareNum.truncateToDouble() == fareNum ? 0 : 2)}'
          : 'Completed';
      title = 'Ride Completed';
      subtitle = fareNum != null && fareNum > 0
          ? 'Total: $fare'
          : 'Thank you for riding with us';
      icon = Icons.check_circle_outline;
      color = AppColors.accentStrong;
    } else if (RideStatus.isCancelled(status)) {
      if (_isDeclined) {
        title = 'Driver Declined';
        subtitle = 'Your ride was declined by the driver';
        icon = Icons.cancel_rounded;
        color = AppColors.accentRed;
      } else {
        final by = _rideRaw['cancelledBy']?.toString();
        title = 'Ride Cancelled';
        subtitle = by != null && by.isNotEmpty
            ? 'Cancelled by $by'
            : 'Ride has been cancelled';
        icon = Icons.cancel_outlined;
        color = AppColors.accentRed;
      }
    } else {
      title = 'Waiting for driver';
      subtitle = 'Please hold tight...';
      icon = Icons.hourglass_empty;
      color = AppColors.accentYellow;
    }

    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 18,
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.body.copyWith(color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverCard(
    Map<String, String> driver,
    Color card,
    Color text,
    Color sub,
  ) {
    final name = driver['name'] ?? 'Driver';
    final phone = driver['phone'];
    final vehicle = driver['vehicle'] ?? '—';
    final rating = driver['rating'] ?? '—';
    final eta = driver['eta'] ?? _rideRaw['eta']?.toString();

    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Driver',
                style: AppTextStyles.cardTitle.copyWith(color: text),
              ),
              Row(
                children: [
                  Icon(Icons.star, color: AppColors.accentYellow, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    rating,
                    style: TextStyle(color: text, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: TextStyle(
              color: text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: sub),
                const SizedBox(width: 8),
                Text(phone, style: TextStyle(color: text, fontSize: 13)),
              ],
            ),
          ],
          if (vehicle.isNotEmpty && vehicle != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                CategoryVehicleImage(
                  vehicleType:
                      _driverInfo?['vehicleType']?.toString() ??
                      _rideRaw['vehicleType']?.toString() ??
                      widget.rideType,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vehicle,
                    style: TextStyle(color: text, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (eta != null && eta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: AppColors.accentStrong),
                const SizedBox(width: 8),
                Text(
                  'ETA: $eta',
                  style: TextStyle(
                    color: AppColors.accentStrong,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          // Chat button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                if (widget.rideId.isEmpty || _userId.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      rideId: widget.rideId,
                      senderId: _userId,
                      senderModel: 'user',
                      receiverId: _resolveDriverId(),
                      otherPartyName: name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text('Message Driver'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentStrong,
                side: BorderSide(
                  color: AppColors.accentStrong.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard(Color card, Color text, Color sub) {
    final pickup =
        _rideRaw['pickupLocation']?.toString() ??
        _rideRaw['pickup']?.toString() ??
        widget.pickup;
    final dropoff =
        _rideRaw['dropoffLocation']?.toString() ??
        _rideRaw['destination']?.toString() ??
        _rideRaw['destinationLocation']?.toString() ??
        widget.destination;
    final rideType =
        _rideRaw['rideType']?.toString() ??
        _rideRaw['vehicleType']?.toString() ??
        widget.rideType;
    final rawFareLC =
        _rideRaw['fare'] ?? widget.rideData?['fare'] ?? widget.ride?.fare;
    final fareNumLC = rawFareLC is num
        ? rawFareLC
        : num.tryParse(rawFareLC?.toString() ?? '');
    // Show fare if it's a positive number. For pending rides fare is the
    // estimated/fixed fare set at booking time — always show it.
    final fareDisplay = fareNumLC != null && fareNumLC > 0
        ? '₹${fareNumLC.toStringAsFixed(fareNumLC.truncateToDouble() == fareNumLC ? 0 : 2)}'
        : '—';
    final distanceDisplay = _resolveDistanceDisplay();
    final durationDisplay = _resolveDurationDisplay();

    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Trip Details',
                style: AppTextStyles.cardTitle.copyWith(color: text),
              ),
              // rideType badge with category image
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryVehicleImage(vehicleType: rideType, size: 28),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentStrong.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rideType,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      const Icon(
                        Icons.circle,
                        color: AppColors.secondary,
                        size: 14,
                      ),
                      Expanded(
                        child: Container(width: 2, color: sub.withAlpha(50)),
                      ),
                      const Icon(
                        Icons.location_on,
                        color: AppColors.accentRed,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pickup
                        Text(
                          pickup.split(',').first.trim(),
                          style: TextStyle(
                            color: text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (pickup.contains(',')) ...[
                          const SizedBox(height: 2),
                          Text(
                            pickup.substring(pickup.indexOf(',') + 1).trim(),
                            style: TextStyle(color: sub, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Dropoff
                        Text(
                          dropoff.split(',').first.trim(),
                          style: TextStyle(
                            color: text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (dropoff.contains(',')) ...[
                          const SizedBox(height: 2),
                          Text(
                            dropoff.substring(dropoff.indexOf(',') + 1).trim(),
                            style: TextStyle(color: sub, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: sub.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('distance'),
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      distanceDisplay,
                      style: TextStyle(
                        color: distanceDisplay == '—' ? sub : text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('duration'),
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationDisplay,
                      style: TextStyle(
                        color: durationDisplay == '—' ? sub : text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('fare'),
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fareDisplay,
                      style: TextStyle(
                        color: fareDisplay == '—'
                            ? sub
                            : AppColors.accentStrong,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCompletedAt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year;
      return '$day/$month/$year  $hour:$minute $ampm';
    } catch (_) {
      return raw;
    }
  }

  Widget _summaryCard(Color card, Color text, Color sub) {
    final rawFare = _rideRaw['fare'];
    final fareNum = rawFare is num
        ? rawFare
        : num.tryParse(rawFare?.toString() ?? '');
    final fareDisplay = (fareNum != null && fareNum > 0)
        ? '₹${fareNum.toStringAsFixed(fareNum.truncateToDouble() == fareNum ? 0 : 2)}'
        : (_ride?.fare != null &&
                  (_ride!.fare is num) &&
                  (_ride!.fare as num) > 0
              ? '₹${_ride!.fare}'
              : '—');

    final distDisplay = _resolveDistanceDisplay();
    final duration = _resolveDurationDisplay();
    final completedAt = _rideRaw['completedAt']?.toString();
    final notes = _rideRaw['notes']?.toString();

    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.accentStrong,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Trip Summary',
                style: AppTextStyles.cardTitle.copyWith(
                  color: text,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: sub.withValues(alpha: 0.15)),
          const SizedBox(height: 14),

          // Fare
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('totalFare'),
                style: TextStyle(color: sub, fontSize: 13),
              ),
              Text(
                fareDisplay,
                style: TextStyle(
                  color: fareDisplay == '—' ? sub : AppColors.accentStrong,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('distance'),
                style: TextStyle(color: sub, fontSize: 13),
              ),
              Text(
                distDisplay,
                style: TextStyle(
                  color: distDisplay == '—' ? sub : text,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Duration (only show if available)
          if (duration != '—') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('duration'),
                  style: TextStyle(color: sub, fontSize: 13),
                ),
                Text(duration, style: TextStyle(color: text, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Completed At
          if (completedAt != null && completedAt.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Completed At',
                  style: TextStyle(color: sub, fontSize: 13),
                ),
                Text(
                  _formatCompletedAt(completedAt),
                  style: TextStyle(color: text, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Notes
          if (notes != null && notes.isNotEmpty) ...[
            Container(height: 1, color: sub.withValues(alpha: 0.15)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: sub),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notes,
                    style: TextStyle(
                      color: sub,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
