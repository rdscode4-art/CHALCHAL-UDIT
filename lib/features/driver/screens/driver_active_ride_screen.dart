import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/widgets/chat_screen.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/map_utils.dart';
import '../../../core/services/ride_status.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/localization/app_localizations.dart';

/// Shown to the driver immediately after the ride is accepted.
/// Displays a live trip timer, the Google Maps route on a map, trip details,
/// and a "Complete Ride" button.
class DriverActiveRideScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String destination;
  final String rideType;
  final String distance;
  final String duration;

  /// Fare set by the passenger at assignment time — seeded immediately so
  /// the driver sees it before the first API round-trip completes.
  final String? fare;

  const DriverActiveRideScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.destination,
    required this.rideType,
    required this.distance,
    required this.duration,
    this.fare,
  });

  @override
  State<DriverActiveRideScreen> createState() => _DriverActiveRideScreenState();
}

class _DriverActiveRideScreenState extends State<DriverActiveRideScreen> {
  // ── Timer ──────────────────────────────────────────────────────────────────
  late final Stopwatch _stopwatch;
  late final Timer _ticker;
  Timer? _statusPollTimer;
  Timer? _locationEmitTimer;
  Timer? _progressTimer;
  bool _completing = false;
  bool _handlingCancel = false;
  bool _cancellingRide = false;
  bool _rideStarted = false; // Track if ride has been started
  StreamSubscription<Position>? _positionSubscription;

  // ── Ride Data State (fetched from API) ──────────────────────────────────────
  String _actualPickup = '';
  String _actualDestination = '';
  String _actualDistance = '—';
  String _actualDuration = '—';
  String _actualRideType = '';
  String? _actualFare;
  String _passengerName = '';
  String _passengerPhone = '—';
  bool _dataFetched = false;

  // ── Progress State ─────────────────────────────────────────────────────────
  int _progressPercent = 0;
  int _routeIndex = 0;

  // ── Map / route ────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  bool _loadingRoute = true;
  List<LatLng> _routePoints = []; // full route polyline
  List<LatLng> _remainingRoutePoints =
      []; // ahead-of-driver slice shown in color
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  LatLng? _driverLatLng; // Live driver GPS position
  double _driverBearing = 0.0; // degrees — updated on every GPS tick
  BitmapDescriptor? _driverIcon; // Custom vehicle emoji marker

  // Live tracking actual metrics
  double _actualDistanceTraveledKm = 0.0;
  Position? _lastTrackedPosition;
  DateTime? _rideStartTime;
  DateTime? _lastDbLocationUpdateTime;
  LatLng? _lastDbUploadedLatLng;

  Future<void> _updateDbLocation(double lat, double lng) async {
    final now = DateTime.now();
    if (_lastDbLocationUpdateTime != null &&
        now.difference(_lastDbLocationUpdateTime!).inSeconds < 2) {
      return;
    }
    // Removed the distance filter so it updates every 2 seconds continuously
    _lastDbLocationUpdateTime = now;
    _lastDbUploadedLatLng = LatLng(lat, lng);
    final driverId = await SessionService.getDriverId();
    if (driverId != null && driverId.isNotEmpty) {
      await ApiService.updateDriverLocationOnly(
        driverId: driverId,
        lat: lat,
        lng: lng,
      );
    }
  }

  // ── Fallback centres (New Delhi) ───────────────────────────────────────────
  static const LatLng _fallbackA = LatLng(28.6139, 77.2090);
  static const LatLng _fallbackB = LatLng(28.7041, 77.1025);

  @override
  void initState() {
    super.initState();
    // Initialize with passed data as fallback
    _actualPickup = widget.pickup;
    _actualDestination = widget.destination;
    _actualDistance = widget.distance;
    _actualDuration = widget.duration;
    _actualRideType = widget.rideType;
    // Seed fare immediately from widget so driver sees it before API returns
    if (widget.fare != null && widget.fare!.isNotEmpty) {
      final parsed = ApiService.parseFareValue(widget.fare);
      _actualFare = parsed != null ? parsed.toString() : widget.fare;
    }

    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Fetch complete ride data from API first
    _fetchCompleteRideData();
    _loadRoute();
    _startStatusPolling();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchRideProgress(),
    );
    _locationEmitTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _driverLatLng != null) {
        SocketService().emitLocation(
          rideId: widget.rideId,
          lat: _driverLatLng!.latitude,
          lng: _driverLatLng!.longitude,
        );
        _updateDbLocation(_driverLatLng!.latitude, _driverLatLng!.longitude);
      }
    });
    _fetchRideProgress();

    // Initialize socket connection and location tracking
    SocketService().connect();
    SocketService().joinRide(widget.rideId);
    SocketService().onRouteUpdated((data) {
      if (data['rideId']?.toString() != widget.rideId) return;
      if (!mounted) return;
      final distance = ApiService.formatDistanceDisplay(
        data['distance'] ?? data['distanceKm'],
      );
      final duration = ApiService.formatDurationDisplay(
        data['duration'] ?? data['durationMin'],
      );
      setState(() {
        if (distance != '—') _actualDistance = distance;
        if (duration != '—') _actualDuration = duration;
      });
    });
    _startLocationTracking();
  }

  void _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    // Pre-load custom vehicle 3D marker matching vehicle type
    final vType = _actualRideType.isNotEmpty
        ? _actualRideType
        : widget.rideType;
    final icon = await MapUtils.get3DVehicleMarkerForType(vType);
    if (mounted) setState(() => _driverIcon = icon);

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // emit every 5 metres
          ),
        ).listen((Position position) {
          if (!mounted) return;
          final latLng = LatLng(position.latitude, position.longitude);

          double distanceGained = 0.0;
          if (_lastTrackedPosition != null && _rideStarted) {
            distanceGained =
                Geolocator.distanceBetween(
                  _lastTrackedPosition!.latitude,
                  _lastTrackedPosition!.longitude,
                  position.latitude,
                  position.longitude,
                ) /
                1000.0; // convert to km
          }

          final isFirstLocation = _driverLatLng == null;

          // Compute heading bearing from previous → new position
          double newBearing = _driverBearing;
          if (_driverLatLng != null) {
            newBearing = MapUtils.calculateBearing(_driverLatLng!, latLng);
          } else if (_rideStarted && _destLatLng != null) {
            newBearing = MapUtils.calculateBearing(latLng, _destLatLng!);
          } else if (!_rideStarted && _pickupLatLng != null) {
            newBearing = MapUtils.calculateBearing(latLng, _pickupLatLng!);
          }

          setState(() {
            _driverLatLng = latLng;
            _driverBearing = newBearing;
            _lastTrackedPosition = position;
            if (_rideStarted) {
              _actualDistanceTraveledKm += distanceGained;
              // Trim traveled portion — keep only points ahead of the driver
              _trimTraveledRoute(latLng);
            } else {
              _remainingRoutePoints = List.of(_routePoints);
            }
          });

          // Broadcast live position via Socket.IO → user sees it on map
          SocketService().emitLocation(
            rideId: widget.rideId,
            lat: position.latitude,
            lng: position.longitude,
          );

          // Also update coordinates in the backend database fallback
          _updateDbLocation(position.latitude, position.longitude);

          if (isFirstLocation) {
            _loadRoute();
          } else {
            _animateCamera3D();
          }
        });
  }

  /// Trims the route polyline so only the portion ahead of [driverPos] is
  /// shown in the colored "remaining" polyline. Finds the closest point on the
  /// full route and slices from there forward.
  void _trimTraveledRoute(LatLng driverPos) {
    if (_routePoints.isEmpty) return;

    int closestIndex = 0;
    double minDist = double.infinity;

    for (int i = 0; i < _routePoints.length; i++) {
      final d = MapUtils.haversineKm(driverPos, _routePoints[i]) * 1000;
      if (d < minDist) {
        minDist = d;
        closestIndex = i;
      }
    }

    // Start the remaining slice from the driver's actual current position
    _remainingRoutePoints = [driverPos, ..._routePoints.sublist(closestIndex)];
  }

  void _stopStatusPolling() {
    _statusPollTimer = null;
  }

  void _startStatusPolling() {
    if (_statusPollTimer != null) return;
    _pollRideStatus();
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollRideStatus(),
    );
  }

  Future<void> _pollRideStatus() async {
    if (!mounted || widget.rideId.isEmpty || _handlingCancel) return;

    try {
      final res = await ApiService.getRide(widget.rideId);
      if (!mounted) return;

      if (res.statusCode == 404) {
        _stopStatusPolling();
        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
        return;
      }

      if (!res.success) return;

      final raw = Map<String, dynamic>.from(res.data);
      final status = RideStatus.resolveEffectiveStatus(
        raw,
        raw['status']?.toString() ?? '',
      );

      debugPrint('[DRIVER_POLL] GET /rides/${widget.rideId} → $status');

      if (RideStatus.isCancelled(status)) {
        await _handleUserCancelledRide();
        return;
      }

      if (RideStatus.isOngoing(status)) {
        setState(() {
          _rideStarted = true;
          _rideStartTime ??= DateTime.now();
        });
      }

      // Prefer pickupLocation/dropoffLocation (passenger's actual addresses)
      // over 'pickup'/'destination' which may contain driver location
      final pickup =
          raw['pickupLocation']?.toString() ?? raw['pickup']?.toString() ?? '';
      final destination =
          raw['dropoffLocation']?.toString() ??
          raw['destination']?.toString() ??
          '';
      if (pickup.isNotEmpty) _actualPickup = pickup;
      if (destination.isNotEmpty) _actualDestination = destination;
      // Only update fare from poll if we get a valid positive value —
      // never overwrite a known fare with null/zero (backend may reset on start)
      final polledFare = ApiService.resolveRideFare(raw);
      if (polledFare != null && polledFare > 0) {
        _actualFare = polledFare.toString();
      }

      if (status == 'completed' || RideStatus.isCompleted(status)) {
        _stopStatusPolling();
        _progressTimer?.cancel();
        _ticker.cancel();
        _stopwatch.stop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('rideComplete')),
            backgroundColor: AppColors.secondary,
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
      }
    } catch (e) {
      debugPrint('ERROR [DRIVER_POLL] error: $e');
    }
  }

  Future<void> _handleUserCancelledRide() async {
    if (_handlingCancel) return;
    _handlingCancel = true;
    _stopStatusPolling();
    _ticker.cancel();
    _stopwatch.stop();

    final driverId = await SessionService.getDriverId();
    if (driverId != null && driverId.isNotEmpty) {
      await ApiService.updateDriverStatus(
        driverId: driverId,
        status: 'online',
        available: true,
      );
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('rideCancelled')),
        content: Text(context.tr('rideCancelledByRider')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.popUntil(context, (r) => r.isFirst);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    SocketService().leaveRide(widget.rideId);
    _ticker.cancel();
    _progressTimer?.cancel();
    _stopStatusPolling();
    _stopwatch.stop();
    super.dispose();
  }

  // SUCCESS CRITICAL FIX #2: Protect back button during active ride (for future implementation)
  // In a complete implementation, this would be called during build:
  // return WillPopScope(onWillPop: _onWillPop, child: Scaffold(...));
  // ── Helpers ────────────────────────────────────────────────────────────────
  /// Fetch complete ride data from API to ensure accuracy
  Future<void> _fetchCompleteRideData() async {
    if (widget.rideId.isEmpty) {
      debugPrint('ERROR No ride ID to fetch complete data');
      return;
    }

    try {
      debugPrint('📡 Fetching complete ride data for: ${widget.rideId}');
      final res = await ApiService.getRide(widget.rideId);

      if (!mounted) return;

      if (res.success) {
        final rideData = ApiService.unwrapRidePayload(res.data);

        // Extract all ride details from API response
        // Backend field names: pickupLocation = passenger's pickup,
        // dropoffLocation = passenger's destination.
        // The 'pickup' field may contain driver location — prefer pickupLocation.
        final pickup =
            rideData['pickupLocation']?.toString().trim() ??
            rideData['pickup']?.toString().trim() ??
            '';
        final destination =
            rideData['dropoffLocation']?.toString().trim() ??
            rideData['destination']?.toString().trim() ??
            rideData['dropoff']?.toString().trim() ??
            '';
        final apiDistance = ApiService.formatDistanceDisplay(
          rideData['distance'] ??
              rideData['distanceKm'] ??
              rideData['distance_km'],
        );
        final apiDuration = ApiService.formatDurationDisplay(
          rideData['duration'] ??
              rideData['durationMin'] ??
              rideData['duration_min'],
        );
        final widgetDistance = ApiService.formatDistanceDisplay(
          widget.distance,
        );
        final widgetDuration = ApiService.formatDurationDisplay(
          widget.duration,
        );
        final distance = apiDistance != '—' ? apiDistance : widgetDistance;
        final duration = apiDuration != '—' ? apiDuration : widgetDuration;
        final rideType =
            rideData['rideType']?.toString() ??
            rideData['vehicleType']?.toString() ??
            '';
        // Prefer passenger-set fare; never overwrite a known fare with null/zero
        final apiFare = ApiService.resolveRideFare(rideData);
        final fareToUse = (apiFare != null && apiFare > 0)
            ? apiFare.toString()
            : _actualFare; // keep existing if API returns nothing

        final passengerName =
            rideData['passengerName']?.toString() ??
            rideData['riderName']?.toString() ??
            '';
        final passengerPhone =
            rideData['passengerPhone']?.toString() ??
            rideData['riderPhone']?.toString() ??
            '—';

        debugPrint('SUCCESS Complete ride data fetched:');
        debugPrint('   Pickup: $pickup');
        debugPrint('   Destination: $destination');
        debugPrint('   Distance: $distance');
        debugPrint('   Duration: $duration');
        debugPrint('   Ride Type: $rideType');
        debugPrint('   Fare: ${fareToUse ?? "N/A"}');
        debugPrint('   Passenger Name: $passengerName');
        debugPrint('   Passenger Phone: $passengerPhone');

        // Update state with real data from API
        if (mounted) {
          setState(() {
            _actualPickup = pickup.isEmpty ? widget.pickup : pickup;
            _actualDestination = destination.isEmpty
                ? widget.destination
                : destination;
            _actualDistance = distance;
            _actualDuration = duration;
            _actualRideType = rideType.isEmpty ? widget.rideType : rideType;
            _actualFare = fareToUse;
            _passengerName = passengerName;
            _passengerPhone = passengerPhone;
            _dataFetched = true;
          });

          // Reload route with real coordinates if they differ
          if (_actualPickup != widget.pickup ||
              _actualDestination != widget.destination) {
            debugPrint(
              'Locations changed, reloading route with real coordinates',
            );
            _loadRoute();
          }
        }
      } else {
        debugPrint(
          'WARNING Failed to fetch complete ride data: ${res.errorMessage}',
        );
        // Keep using passed data as fallback
        if (mounted) {
          setState(() => _dataFetched = true);
        }
      }
    } catch (e) {
      debugPrint('ERROR Error fetching complete ride data: $e');
      // Keep using passed data as fallback
      if (mounted) {
        setState(() => _dataFetched = true);
      }
    }
  }

  Future<void> _fetchRideProgress() async {
    if (widget.rideId.isEmpty) return;

    final progressRes = await ApiService.getRideProgress(widget.rideId);
    if (!mounted) return;

    if (progressRes.success) {
      final percent = progressRes.data['progressPercent'] as int?;
      setState(() {
        if (percent != null) {
          _progressPercent = percent;
          if (_routePoints.isNotEmpty) {
            _routeIndex = ((percent / 100) * (_routePoints.length - 1))
                .round()
                .clamp(0, _routePoints.length - 1);
          }
        }
      });
    }
  }

  Future<void> _loadRoute() async {
    if (!mounted) return;
    setState(() => _loadingRoute = true);

    _pickupLatLng = await MapUtils.geocode(_actualPickup) ?? _fallbackA;
    _destLatLng = await MapUtils.geocode(_actualDestination) ?? _fallbackB;

    LatLng originPoint;
    LatLng destPoint;

    if (!_rideStarted) {
      // Route to pickup: from driver's location to pickup
      originPoint = _driverLatLng ?? _pickupLatLng ?? _fallbackA;
      destPoint = _pickupLatLng ?? _fallbackA;
    } else {
      // Route to destination: from driver/pickup to destination
      originPoint = _driverLatLng ?? _pickupLatLng ?? _fallbackA;
      destPoint = _destLatLng ?? _fallbackB;
    }

    final result = await MapUtils.getDirections(
      origin: originPoint,
      destination: destPoint,
    );
    _routePoints = result.points;
    // When ride starts or route reloads, reset remaining to the full route.
    // The trim logic will narrow it on every subsequent GPS tick.
    _remainingRoutePoints = List.of(_routePoints);

    if (mounted) setState(() => _loadingRoute = false);

    // Animate camera to 3D navigation view
    Future.delayed(const Duration(milliseconds: 300), () {
      _animateCamera3D();
    });
  }

  void _animateCamera3D() {
    if (_mapController == null) return;
    final driverPos = _driverLatLng ?? _pickupLatLng ?? _fallbackA;

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: driverPos,
          zoom: 17.0,
          // 45° tilt gives the Google Maps navigation look
          tilt: _rideStarted ? 45.0 : 0.0,
          // Rotate the map to match the direction of travel
          bearing: _driverBearing,
        ),
      ),
    );
  }

  Future<String?> _resolveFareForCompletion() async {
    final cached = ApiService.parseFareValue(_actualFare);
    if (cached != null) return cached.toString();

    if (widget.rideId.isEmpty) return null;

    final res = await ApiService.getRide(widget.rideId);
    if (!res.success) return null;

    final fare = ApiService.resolveRideFare(res.data);
    if (fare == null) return null;

    if (mounted) setState(() => _actualFare = fare.toString());
    return fare.toString();
  }

  void _completeRide() async {
    if (_completing) return; // Prevent double-tap

    // Check if ride was started
    if (!_rideStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('pleaseStartRideFirst')),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Use fare set by passenger — driver cannot modify it
    final resolvedFare = await _resolveFareForCompletion();
    if (resolvedFare == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('fareRequiredToComplete')),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final fareToUse = resolvedFare;

    // Show read-only confirmation dialog — driver views fare, cannot edit
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textCol = isDark ? AppColors.darkOnSurface : AppColors.textDark;
        final bgCol = isDark ? AppColors.darkSurface : AppColors.surface;
        final subCol = isDark ? AppColors.textLight : AppColors.textGrey;

        return AlertDialog(
          backgroundColor: bgCol,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            context.tr('completeRide'),
            style: TextStyle(
              color: textCol,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('confirmRideCompletion'),
                style: TextStyle(color: subCol, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentStrong.withAlpha(18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accentStrong.withAlpha(60),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.currency_rupee,
                      color: AppColors.secondary,
                      size: 24,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fareToUse,
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  context.tr('fareSetByPassenger'),
                  style: TextStyle(color: subCol, fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.tr('cancel'),
                style: const TextStyle(
                  color: AppColors.accentRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('confirmComplete'),
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return; // Driver cancelled

    setState(() => _completing = true);

    debugPrint('🏁 [DRIVER_COMPLETE] Attempting to complete ride:');
    debugPrint('   RideID: ${widget.rideId}');
    debugPrint('   Pickup: $_actualPickup');
    debugPrint('   Destination: $_actualDestination');
    debugPrint('   Fare (passenger-set): $fareToUse');

    try {
      // Get driver ID from session
      final driverId = await SessionService.getDriverId() ?? '';

      if (driverId.isEmpty) {
        throw Exception('Driver ID not available');
      }

      // Calculate actual trip duration
      final durationMinutes = _rideStartTime != null
          ? DateTime.now().difference(_rideStartTime!).inMinutes
          : _stopwatch.elapsed.inMinutes;
      final finalDurationMins = durationMinutes.clamp(1, 999);
      final durationStr = '$finalDurationMins mins';

      // Use the estimated distance from the route preview stored in the backend to ensure consistency
      String distanceStr = _actualDistance;
      double distanceKm =
          double.tryParse(_actualDistance.replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0.0;
      if (distanceStr.isEmpty || distanceStr == '—' || distanceKm == 0.0) {
        distanceKm = _actualDistanceTraveledKm;
        distanceStr = '${distanceKm.toStringAsFixed(1)} km';
      }

      // Complete ride using the passenger-set fare
      final fare = fareToUse;
      final res = await ApiService.completeRideByDriver(
        rideId: widget.rideId,
        driverId: driverId,
        fare: fare,
        notes: 'Ride completed successfully by driver',
        distance: distanceStr,
        duration: durationStr,
        distanceKm: distanceKm,
      );

      if (!mounted) return;

      if (res.success) {
        SocketService().emitStatusChange(
          rideId: widget.rideId,
          status: RideStatus.completed,
        );

        debugPrint('SUCCESS [DRIVER_COMPLETE] SUCCESS — status completed');
        debugPrint('   Final Fare: $fare');

        _stopStatusPolling();
        _progressTimer?.cancel();
        _ticker.cancel();
        _stopwatch.stop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 ${context.tr('rideComplete')}! ${context.tr('fare')}: ₹$fare',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.secondary,
          ),
        );

        // Navigate back to driver home screen with a slight delay
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          // Use Navigator.pop instead of popUntil to ensure clean navigation
          Navigator.of(context).pop(true); // Return true to indicate success
        }
      } else {
        debugPrint('ERROR [DRIVER_COMPLETE] FAILED - Backend error:');
        debugPrint('   Error: ${res.errorMessage}');
        debugPrint('   Response Data: ${res.data}');

        setState(() => _completing = false);

        // Fallback for offline mode/demo mode
        final isOffline =
            res.errorMessage?.toLowerCase().contains('connection') ?? false;

        if (isOffline) {
          debugPrint(
            'WARNING [DRIVER_COMPLETE] Offline mode - completing locally',
          );

          _stopStatusPolling();
          _progressTimer?.cancel();
          _ticker.cancel();
          _stopwatch.stop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🎉 ${context.tr('rideComplete')}! (Offline) ${context.tr('fare')}: ₹${_actualFare ?? "0"}',
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.secondary,
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } else {
          // Show error and allow retry
          setState(() => _completing = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res.errorMessage ??
                    'Failed to complete ride. Please try again.',
              ),
              backgroundColor: AppColors.accentRed,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: context.tr('retry'),
                textColor: Colors.white,
                onPressed: _completeRide,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('ERROR [DRIVER_COMPLETE] Exception: $e');

      if (!mounted) return;

      setState(() => _completing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing ride: ${e.toString()}'),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: context.tr('retry'),
            textColor: Colors.white,
            onPressed: _completeRide,
          ),
        ),
      );
    }
  }

  // ── OTP helpers ───────────────────────────────────────────────────────────────
  /// Same deterministic algorithm as user-side so both match without backend.
  String _deriveOtp(String rideId, String salt) {
    if (rideId.isEmpty) return '0000';
    // Must match user-side: utf8 encode 'rideId:salt'
    final input = '$rideId:$salt';
    final bytes = input.runes.map((r) => r & 0xFF).toList();
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7FFFFFFF;
    }
    return (1000 + (hash % 9000)).toString();
  }

  Future<void> _openGoogleMapsNavigation() async {
    final String targetAddress = _rideStarted
        ? _actualDestination
        : _actualPickup;
    if (targetAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('loadingLocation') ?? 'Location is not ready yet.',
          ),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }
    final LatLng? coords = _rideStarted ? _destLatLng : _pickupLatLng;
    final bool hasValidCoords =
        coords != null &&
        coords.latitude != 0.0 &&
        coords.latitude != _fallbackA.latitude &&
        coords.latitude != _fallbackB.latitude;

    final String destinationParam = hasValidCoords
        ? '${coords.latitude},${coords.longitude}'
        : targetAddress;

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destinationParam)}&travelmode=driving',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (e) {
      debugPrint('Error launching Google Maps: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  void _promptOtpAndStartRide() async {
    final TextEditingController otpController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textCol = isDark
                ? AppColors.darkOnSurface
                : AppColors.textDark;
            final bgCol = isDark ? AppColors.darkSurface : AppColors.surface;

            return AlertDialog(
              backgroundColor: bgCol,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Enter OTP to Start Ride',
                style: TextStyle(
                  color: textCol,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please ask the rider for the 4-digit OTP shown on their screen.',
                    style: TextStyle(
                      color: isDark ? AppColors.textLight : AppColors.textGrey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: false,
                    style: TextStyle(
                      color: textCol,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      errorText: errorText,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (val) {
                      if (errorText != null) {
                        setDialogState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    context.tr('cancel'),
                    style: const TextStyle(
                      color: AppColors.accentRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final enteredOtp = otpController.text.trim();
                    final expectedOtp = _deriveOtp(widget.rideId, 'start');
                    if (enteredOtp == expectedOtp) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() {
                        errorText =
                            'Invalid OTP. Ask the passenger for their Start OTP.';
                      });
                    }
                  },
                  child: const Text(
                    'Verify & Start',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      _startRide();
    }
  }

  void _promptOtpAndCompleteRide() async {
    // Check if ride was started
    if (!_rideStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('pleaseStartRideFirst')),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final TextEditingController otpController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textCol = isDark
                ? AppColors.darkOnSurface
                : AppColors.textDark;
            final bgCol = isDark ? AppColors.darkSurface : AppColors.surface;

            return AlertDialog(
              backgroundColor: bgCol,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Enter OTP to Complete Ride',
                style: TextStyle(
                  color: textCol,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please ask the rider for the 4-digit OTP to complete the ride.',
                    style: TextStyle(
                      color: isDark ? AppColors.textLight : AppColors.textGrey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: false,
                    style: TextStyle(
                      color: textCol,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      errorText: errorText,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (val) {
                      if (errorText != null) {
                        setDialogState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    context.tr('cancel'),
                    style: const TextStyle(
                      color: AppColors.accentRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final enteredOtp = otpController.text.trim();
                    final expectedOtp = _deriveOtp(widget.rideId, 'complete');
                    if (enteredOtp == expectedOtp) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() {
                        errorText =
                            'Invalid OTP. Ask the passenger for their Complete OTP.';
                      });
                    }
                  },
                  child: const Text(
                    'Verify & Complete',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      _completeRide();
    }
  }

  void _startRide() async {
    debugPrint('🚀 [DRIVER_START] Starting ride: ${widget.rideId}');

    final driverId = await SessionService.getDriverId();
    debugPrint('[DRIVER_START] Driver ID: $driverId');

    final distanceKm =
        ApiService.parseDistanceKm(_actualDistance) ??
        ApiService.parseDistanceKm(widget.distance);
    final durationMin =
        ApiService.parseDurationMin(_actualDuration) ??
        ApiService.parseDurationMin(widget.duration);

    final res = await ApiService.startRide(
      rideId: widget.rideId,
      driverId: driverId ?? '',
      distance: _actualDistance != '—' ? _actualDistance : widget.distance,
      distanceKm: distanceKm,
      duration: _actualDuration != '—' ? _actualDuration : widget.duration,
      durationMin: durationMin,
      fare: _actualFare ?? widget.fare, // keep fare on backend during start
    );

    if (!mounted) return;

    debugPrint(
      '📡 [DRIVER_START] API response - success: ${res.success}, error: ${res.errorMessage}',
    );

    if (res.success) {
      final startedAt = DateTime.now().toUtc().toIso8601String();
      final statusFromApi = RideStatus.normalize(
        res.get<String>('status') ?? res.get<String>('rideStatus') ?? '',
      );
      final statusToSet = RideStatus.isOngoing(statusFromApi)
          ? statusFromApi
          : 'started';

      await ApiService.updateRideStatus(
        rideId: widget.rideId,
        status: statusToSet,
        extraFields: {
          'startedAt': startedAt,
          // Re-send fare so status update doesn't clear it
          if (_actualFare != null && _actualFare!.isNotEmpty)
            ...ApiService.fareFieldsFromValue(_actualFare!),
        },
      );

      SocketService().emitStatusChange(
        rideId: widget.rideId,
        status: statusToSet,
      );

      debugPrint('SUCCESS [DRIVER_START] Ride started — status $statusToSet');
      setState(() {
        _rideStarted = true;
        _rideStartTime = DateTime.now();
      });

      _loadRoute();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('tripStarted')}!'),
          backgroundColor: AppColors.secondary,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      debugPrint(
        'ERROR [DRIVER_START] Failed to start ride: ${res.errorMessage}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.errorMessage ?? 'Failed to start ride'),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _cancelRideByDriver() async {
    if (_cancellingRide) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textCol = isDark ? AppColors.darkOnSurface : AppColors.textDark;
        final bgCol = isDark ? AppColors.darkSurface : AppColors.surface;

        return AlertDialog(
          backgroundColor: bgCol,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            context.tr('cancelRideQuestion'),
            style: TextStyle(
              color: textCol,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            context.tr('cancelRideConfirm'),
            style: TextStyle(
              color: isDark ? AppColors.textLight : AppColors.textGrey,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.tr('cancel'),
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('yesCancel'),
                style: const TextStyle(
                  color: AppColors.accentRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _cancellingRide = true);

    try {
      debugPrint('🚨 [DRIVER_CANCEL] Cancelling ride: ${widget.rideId}');
      final res = await ApiService.cancelRideByUser(
        rideId: widget.rideId,
        cancelledBy: 'driver',
      );

      if (!mounted) return;

      if (res.success) {
        // Notify socket of status change to cancelled
        SocketService().emitStatusChange(
          rideId: widget.rideId,
          status: RideStatus.cancelled,
        );

        // Put driver back online/available
        final driverId = await SessionService.getDriverId();
        if (driverId != null && driverId.isNotEmpty) {
          await ApiService.updateDriverStatus(
            driverId: driverId,
            status: 'online',
            available: true,
          );
        }

        _stopStatusPolling();
        _progressTimer?.cancel();
        _ticker.cancel();
        _stopwatch.stop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('cancelSuccess')),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true); // Return back to home
        }
      } else {
        setState(() => _cancellingRide = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorMessage ?? 'Failed to cancel ride'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } catch (e) {
      debugPrint('ERROR [DRIVER_CANCEL] Exception: $e');
      if (mounted) {
        setState(() => _cancellingRide = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final card = isDark ? AppColors.darkSurface : AppColors.surface;
    final cardSoft = isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark
        ? AppColors.darkOnSurface.withAlpha((0.6 * 255).round())
        : AppColors.textGrey;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          context.tr('rideInProgress'),
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withAlpha(160),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _dataFetched
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Passenger Information ─────────────────────────────────
                    // Always shown once ride data is fetched so the chat button
                    // is accessible even if passengerName hasn't loaded yet.
                    GlassCard(
                      borderRadius: BorderRadius.circular(24),
                      color: card,
                      border: Border.all(color: border),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  color: AppColors.secondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('passengerInformation'),
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 16,
                                    color: text,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Passenger avatar + name/phone
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppColors.secondary
                                      .withAlpha(50),
                                  child: Icon(
                                    Icons.person,
                                    color: AppColors.secondary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _passengerName.isNotEmpty
                                            ? _passengerName
                                            : '—',
                                        style: AppTextStyles.heading.copyWith(
                                          fontSize: 15,
                                          color: text,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (_passengerPhone.isNotEmpty &&
                                          _passengerPhone != '—') ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _passengerPhone,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: sub,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // ── Chat button ───────────────────────────────
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final driverId =
                                      await SessionService.getDriverId();
                                  if (!mounted ||
                                      driverId == null ||
                                      driverId.isEmpty ||
                                      widget.rideId.isEmpty) {
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        rideId: widget.rideId,
                                        senderId: driverId,
                                        senderModel: 'driver',
                                        otherPartyName:
                                            _passengerName.isNotEmpty
                                            ? _passengerName
                                            : 'Passenger',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                ),
                                label: const Text('Message Passenger'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.secondary,
                                  side: BorderSide(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Detailed Ride Information ────────────────────────────
                    GlassCard(
                      borderRadius: BorderRadius.circular(24),
                      color: card,
                      border: Border.all(color: border),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outlined,
                                  color: AppColors.secondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Trip Details',
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 16,
                                    color: text,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Column(
                                      children: [
                                        const Icon(
                                          Icons.circle,
                                          color: AppColors.secondary,
                                          size: 14,
                                        ),
                                        Expanded(
                                          child: Container(
                                            width: 2,
                                            color: border.withAlpha(100),
                                          ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Pickup
                                          Text(
                                            _actualPickup
                                                .split(',')
                                                .first
                                                .trim(),
                                            style: TextStyle(
                                              color: text,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (_actualPickup.contains(',')) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              _actualPickup
                                                  .substring(
                                                    _actualPickup.indexOf(',') +
                                                        1,
                                                  )
                                                  .trim(),
                                              style: TextStyle(
                                                color: sub,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          const SizedBox(height: 20),
                                          // Destination
                                          Text(
                                            _actualDestination
                                                .split(',')
                                                .first
                                                .trim(),
                                            style: TextStyle(
                                              color: text,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (_actualDestination.contains(
                                            ',',
                                          )) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              _actualDestination
                                                  .substring(
                                                    _actualDestination.indexOf(
                                                          ',',
                                                        ) +
                                                        1,
                                                  )
                                                  .trim(),
                                              style: TextStyle(
                                                color: sub,
                                                fontSize: 12,
                                              ),
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
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Trip info chips ──────────────────────────────────────────
                    Row(
                      children: [
                        // rideType chip — uses category image
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: cardSoft,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CategoryVehicleImage(
                                  vehicleType: _actualRideType.isEmpty
                                      ? 'auto'
                                      : _actualRideType,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _actualRideType.isEmpty
                                        ? 'N/A'
                                        : _actualRideType,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: text,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _chip(
                          cardSoft,
                          border,
                          text,
                          Icons.straighten,
                          _actualDistance,
                        ),
                        const SizedBox(width: 10),
                        _chip(
                          cardSoft,
                          border,
                          text,
                          Icons.access_time,
                          _actualDuration,
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ── Fare Display (read-only — set by passenger on assign) ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentStrong.withAlpha(
                          (0.10 * 255).round(),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.accentStrong.withAlpha(
                            (0.28 * 255).round(),
                          ),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('estimatedFare'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: text,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_atm_rounded,
                                size: 20,
                                color: AppColors.accentStrong,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (_actualFare != null && _actualFare!.isNotEmpty)
                                    ? '₹$_actualFare'
                                    : '—',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: AppColors.accentStrong,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Progress Bar ──
                    if (_progressPercent > 0) ...[
                      GlassCard(
                        borderRadius: BorderRadius.circular(20),
                        color: card,
                        border: Border.all(color: border),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  context.tr('tripProgress'),
                                  style: AppTextStyles.body.copyWith(
                                    color: text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '$_progressPercent%',
                                  style: TextStyle(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progressPercent / 100.0,
                                minHeight: 8,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.secondary,
                                ),
                                backgroundColor: cardSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 12),

                    // ── Start / Complete ride buttons ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: !_rideStarted
                              ? CustomButton(
                                  label: context.tr('startRide'),
                                  color: AppColors.secondary,
                                  onPressed: _promptOtpAndStartRide,
                                )
                              : CustomButton(
                                  label: _completing
                                      ? context.tr('completing')
                                      : context.tr('completeRide'),
                                  color: AppColors.secondary,
                                  onPressed: _completing
                                      ? () {}
                                      : _promptOtpAndCompleteRide,
                                ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 58,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _openGoogleMapsNavigation,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.secondary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.zero,
                              backgroundColor: Colors.transparent,
                            ),
                            child: const Icon(
                              Icons.navigation_outlined,
                              color: AppColors.secondary,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_rideStarted) ...[
                      const SizedBox(height: 12),
                      // Info message
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withAlpha(
                            (0.12 * 255).round(),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.accentYellow.withAlpha(
                              (0.4 * 255).round(),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.accentYellow,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.tr('startRidePrompt'),
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.accentYellow
                                      : AppColors.textDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomButton(
                        label: _cancellingRide
                            ? context.tr('cancellingRide')
                            : context.tr('cancelRideBtn'),
                        color: AppColors.accentRed,
                        onPressed: _cancellingRide ? () {} : _cancelRideByDriver,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Live map with route ──────────────────────────────────────
                    GlassCard(
                      borderRadius: BorderRadius.circular(24),
                      color: card,
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 60 : 14),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  color: AppColors.secondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('liveRoute'),
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 16,
                                    color: text,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                // ETA chip — pickup pre-trip, destination during trip
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
                                          _rideStarted
                                              ? (_destLatLng != null
                                                    ? MapUtils.etaString(
                                                        _driverLatLng!,
                                                        _destLatLng!,
                                                      )
                                                    : '—')
                                              : (_pickupLatLng != null
                                                    ? MapUtils.etaString(
                                                        _driverLatLng!,
                                                        _pickupLatLng!,
                                                      )
                                                    : '—'),
                                          style: const TextStyle(
                                            color: AppColors.secondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Map container
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: SizedBox(
                                height: 280,
                                child: _loadingRoute
                                    ? Container(
                                        color: cardSoft,
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(
                                                color: AppColors.secondary,
                                              ),
                                              const SizedBox(height: 14),
                                              Text(
                                                context.tr('loadingRoute'),
                                                style: TextStyle(
                                                  color: sub,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Stack(
                                        children: [
                                          GoogleMap(
                                            onMapCreated:
                                                (
                                                  GoogleMapController
                                                  controller,
                                                ) async {
                                                  _mapController = controller;
                                                  _animateCamera3D();
                                                },
                                            initialCameraPosition:
                                                CameraPosition(
                                                  target:
                                                      _driverLatLng ??
                                                      _pickupLatLng ??
                                                      _fallbackA,
                                                  zoom: 17.0,
                                                  tilt: _rideStarted
                                                      ? 45.0
                                                      : 0.0,
                                                  bearing: _driverBearing,
                                                ),
                                            mapType: MapType.normal,
                                            myLocationEnabled: true,
                                            myLocationButtonEnabled: false,
                                            zoomControlsEnabled: false,
                                            polylines: {
                                              // ── Traveled portion (gray, behind driver)
                                              if (_routePoints.isNotEmpty &&
                                                  _rideStarted)
                                                Polyline(
                                                  polylineId: const PolylineId(
                                                    'traveled',
                                                  ),
                                                  points:
                                                      _remainingRoutePoints
                                                          .isEmpty
                                                      ? _routePoints
                                                      : _routePoints.sublist(
                                                          0,
                                                          (_routePoints.length -
                                                                  _remainingRoutePoints
                                                                      .length +
                                                                  1)
                                                              .clamp(
                                                                0,
                                                                _routePoints
                                                                    .length,
                                                              ),
                                                        ),
                                                  color: Colors.grey.shade400,
                                                  width: 5,
                                                  geodesic: true,
                                                  startCap: Cap.roundCap,
                                                  endCap: Cap.roundCap,
                                                  jointType: JointType.round,
                                                  patterns: [
                                                    PatternItem.dash(12),
                                                    PatternItem.gap(6),
                                                  ],
                                                ),
                                              // ── Remaining route (colored, ahead of driver)
                                              if (_remainingRoutePoints
                                                  .isNotEmpty)
                                                Polyline(
                                                  polylineId: const PolylineId(
                                                    'route',
                                                  ),
                                                  points: _remainingRoutePoints,
                                                  color: AppColors.secondary,
                                                  width: 6,
                                                  geodesic: true,
                                                  startCap: Cap.roundCap,
                                                  endCap: Cap.roundCap,
                                                  jointType: JointType.round,
                                                ),
                                            },
                                            markers: <Marker>{
                                              // Pickup marker — hide once ride started
                                              if (_pickupLatLng != null &&
                                                  !_rideStarted)
                                                Marker(
                                                  markerId: const MarkerId(
                                                    'pickup',
                                                  ),
                                                  position: _pickupLatLng!,
                                                  infoWindow: InfoWindow(
                                                    title: '📍 Pickup',
                                                    snippet: _actualPickup,
                                                  ),
                                                  icon:
                                                      BitmapDescriptor.defaultMarkerWithHue(
                                                        BitmapDescriptor
                                                            .hueBlue,
                                                      ),
                                                ),
                                              // Destination marker
                                              if (_destLatLng != null)
                                                Marker(
                                                  markerId: const MarkerId(
                                                    'destination',
                                                  ),
                                                  position: _destLatLng!,
                                                  infoWindow: InfoWindow(
                                                    title: '🏁 Destination',
                                                    snippet: _actualDestination,
                                                  ),
                                                  icon:
                                                      BitmapDescriptor.defaultMarkerWithHue(
                                                        BitmapDescriptor.hueRed,
                                                      ),
                                                ),
                                              // Live driver marker — rotated to heading
                                              if (_driverLatLng != null)
                                                Marker(
                                                  markerId: const MarkerId(
                                                    'driver',
                                                  ),
                                                  position: _driverLatLng!,
                                                  rotation: _driverBearing,
                                                  flat: true,
                                                  anchor: const Offset(
                                                    0.5,
                                                    0.5,
                                                  ),
                                                  infoWindow: InfoWindow(
                                                    title: '🚗 You',
                                                    snippet: _rideStarted
                                                        ? 'Heading to destination'
                                                        : 'Heading to pickup',
                                                  ),
                                                  icon:
                                                      _driverIcon ??
                                                      BitmapDescriptor.defaultMarkerWithHue(
                                                        BitmapDescriptor
                                                            .hueAzure,
                                                      ),
                                                ),
                                            },
                                          ),
                                          // ── Recenter button ─────────────
                                          if (_driverLatLng != null)
                                            Positioned(
                                              bottom: 12,
                                              right: 12,
                                              child: GestureDetector(
                                                onTap: _animateCamera3D,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withAlpha(230),
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withAlpha(40),
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
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.secondary),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('loadingRideDetails'),
                      style: AppTextStyles.body.copyWith(color: sub),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Small helpers ──────────────────────────────────────────────────────────

  Widget _detailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color text,
    required Color sub,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: sub,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(
    Color soft,
    Color border,
    Color text,
    IconData icon,
    String label,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.secondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
