import 'dart:async';
import 'dart:math' show atan2, cos, pi, sin, sqrt;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/active_ride_storage.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/ride_request_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/widgets/chat_screen.dart';
import '../../../core/localization/app_localizations.dart';
import 'ride_confirmation_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme colour resolver
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  final bool dark;
  const _C(this.dark);
  Color get scaffold => dark ? AppColors.darkBackground : AppColors.background;
  Color get appBar => dark ? AppColors.darkSurface : Colors.white;
  Color get appBarTitle => dark ? AppColors.darkOnSurface : AppColors.textDark;
  Color get card => dark ? AppColors.darkSurface : Colors.white;
  Color get cardSoft =>
      dark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
  Color get border => dark ? AppColors.darkBorder : AppColors.border;
  Color get textPrimary => dark ? AppColors.darkOnSurface : AppColors.textDark;
  Color get textSecondary => dark
      ? AppColors.darkOnSurface.withAlpha((0.65 * 255).round())
      : AppColors.textGrey;
  Color get green => AppColors.secondary;
  Color get yellow => AppColors.accentYellow;
  Color get red => AppColors.accentRed;
  Color get inputFill =>
      dark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
}

// ─────────────────────────────────────────────────────────────────────────────
// Map frontend ride type names to backend enum values
// Frontend: 'bike', 'auto', 'ev', 'sedan', 'suv'
// Backend: 'bike', 'auto', 'ev', 'sedan', 'suv' (lowercase enum format)
// ─────────────────────────────────────────────────────────────────────────────
String _mapRideTypeToEnum(String rideName) {
  final name = rideName.toLowerCase().trim();
  if (name == 'sedan ac' || name == 'luxury') return 'luxury';
  if (name == 'car') return 'car';
  if (name == 'ev') return 'ev';
  if (name == 'auto') return 'auto';
  if (name == 'bike') return 'bike';
  return name;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

// ─────────────────────────────────────────────────────────────────────────────
// Normalise a raw driver map from the backend into the shape the UI expects.
// Backend returns: { _id, name, phone, vehicleNumber, lat, lng, available }
// ─────────────────────────────────────────────────────────────────────────────
Map<String, dynamic> _normaliseDriver(
  Map<String, dynamic> m, {
  double? userLat,
  double? userLng,
}) {
  final driverLat = (m['lat'] as num?)?.toDouble();
  final driverLng = (m['lng'] as num?)?.toDouble();

  String distanceStr = '—';
  String etaStr = '—';
  if (driverLat != null &&
      driverLng != null &&
      userLat != null &&
      userLng != null) {
    final km = _haversineKm(userLat, userLng, driverLat, driverLng);
    distanceStr = km.toStringAsFixed(1);
    // Rough ETA: assume 30 km/h average city speed
    final mins = (km / 30 * 60).round();
    etaStr = mins <= 1 ? '1 min' : '$mins mins';
  }

  // Extract vehicle type from multiple possible fields
  String vehicleType = (m['vehicleType']?.toString() ?? '')
      .trim()
      .toLowerCase();
  if (vehicleType.isEmpty) {
    vehicleType = (m['vehicle_type']?.toString() ?? '').trim().toLowerCase();
  }
  if (vehicleType.isEmpty) {
    vehicleType = (m['type']?.toString() ?? '').trim().toLowerCase();
  }

  // If still empty, try to infer from vehicle name/number
  if (vehicleType.isEmpty) {
    final vehicleName =
        (m['vehicle']?.toString() ?? m['vehicleNumber']?.toString() ?? '')
            .toLowerCase();
    debugPrint(
      '⚠️ [NORMALISE] No explicit vehicleType, inferring from: "$vehicleName"',
    );

    if (vehicleName.contains('bike') ||
        vehicleName.contains('honda') ||
        vehicleName.contains('bajaj')) {
      vehicleType = 'bike';
    } else if (vehicleName.contains('auto') ||
        vehicleName.contains('rickshaw') ||
        vehicleName.contains('tuk')) {
      vehicleType = 'auto';
    } else if (vehicleName.contains('ev') || vehicleName.contains('electric')) {
      vehicleType = 'ev';
    } else if (vehicleName.contains('suv') ||
        vehicleName.contains('mahindra') ||
        vehicleName.contains('xuv')) {
      vehicleType = 'suv';
    } else if (vehicleName.contains('sedan') ||
        vehicleName.contains('maruti') ||
        vehicleName.contains('dzire') ||
        vehicleName.contains('aura') ||
        vehicleName.contains('toyota') ||
        vehicleName.contains('etios')) {
      vehicleType = 'sedan';
    } else {
      // Default to sedan if we can't determine
      debugPrint('⚠️ [NORMALISE] Could not infer type, defaulting to sedan');
      vehicleType = 'sedan';
    }
    debugPrint('   → Inferred vehicleType: "$vehicleType"');
  }

  return {
    'id': m['_id']?.toString() ?? m['id']?.toString() ?? '',
    'name': m['name']?.toString() ?? 'Driver',
    'phone': m['phone']?.toString() ?? '',
    // Backend has no vehicle model — show vehicle number as the vehicle label
    'vehicle': m['vehicleNumber']?.toString() ?? '',
    'vehicleNumber': m['vehicleNumber']?.toString() ?? '',
    // Extract vehicleType from multiple sources or infer from vehicle name
    'vehicleType': vehicleType,
    'eta': distanceStr != '—' ? etaStr : (m['eta']?.toString() ?? etaStr),
    'rating': m['rating']?.toString() ?? '—',
    'status': (m['available'] == true) ? 'Online' : 'Offline',
    'distanceKm': distanceStr != '—' ? distanceStr : (m['distanceKm']?.toString() ?? distanceStr),
    'experience': m['experience']?.toString() ?? '—',
    'lat': driverLat,
    'lng': driverLng,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Available Drivers screen — fetches from backend, search, filter, assign, call
// ─────────────────────────────────────────────────────────────────────────────
class DriversListScreen extends StatefulWidget {
  final String rideType;
  final String pickup;
  final String destination;
  final String rideId;
  final double pickupLat;
  final double pickupLng;

  /// Pre-calculated route distance in km (from SelectRideScreen → Directions API).
  final double? distanceKm;

  /// Pre-calculated route duration in minutes (from SelectRideScreen → Directions API).
  final double? durationMin;

  const DriversListScreen({
    super.key,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.rideId,
    required this.pickupLat,
    required this.pickupLng,
    this.distanceKm,
    this.durationMin,
  });

  @override
  State<DriversListScreen> createState() => _DriversListScreenState();
}

class _DriversListScreenState extends State<DriversListScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<String> _interestedDriverIds = [];
  Timer? _pollingTimer;
  bool _assigning = false;
  String _userId = '';
  DateTime? _searchStartTime;
  final List<String> _rejectedDriverIds = [];

  bool get _hasSearchTimedOut {
    if (_searchStartTime == null) return false;
    return DateTime.now().difference(_searchStartTime!) >=
        const Duration(minutes: 2);
  }

  // FCM foreground listener — refreshes bids when driver taps "I'm Available"
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  // ── Fetch state ────────────────────────────────────────────────────────────
  bool _loading = true;
  String? _fetchError;
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    ActiveRideStorage.save(widget.rideId);
    _searchStartTime = DateTime.now();
    _fetchDrivers();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) _fetchDrivers();
    });
    // Load user ID for chat
    SessionService.getUserId().then((id) {
      if (mounted && id != null && id.isNotEmpty) {
        setState(() => _userId = id);
      }
    });

    // When a driver clicks "I'm Available", the backend sends a push to the
    // user with data.event = 'driver_available'. Immediately refresh the list
    // so the driver appears without waiting for the next polling tick.
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      final event = message.data['event']?.toString() ?? '';
      final msgRideId = message.data['rideId']?.toString() ?? '';
      debugPrint('[FCM] DriversListScreen: event=$event rideId=$msgRideId');
      if ((event == 'driver_available' || event == 'ride_rejected') &&
          (msgRideId.isEmpty || msgRideId == widget.rideId)) {
        debugPrint('[FCM] $event -> refreshing bids');
        if (mounted) _fetchDrivers();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _fcmSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Fetch available drivers from backend ───────────────────────────────────
  //
  // Real rides  → GET /api/user/ride/:rideId/bids
  //   Returns only the drivers who pressed "I'm Available" for this ride.
  //
  // Demo rides (ride_* prefix) → GET /drivers/nearby
  //   Falls back to all nearby drivers so the UI is useful during local testing.
  Future<void> _fetchDrivers() async {
    // Show spinner only on the very first load
    if (_drivers.isEmpty && mounted) {
      setState(() {
        _loading = true;
        _fetchError = null;
      });
    }

    final isRealRide =
        widget.rideId.isNotEmpty && !widget.rideId.startsWith('ride_');

    ApiResponse res;
    if (isRealRide) {
      res = await ApiService.getRideBids(widget.rideId);
      debugPrint(
        '📥 [BIDS] GET /api/user/ride/${widget.rideId}/bids → success=${res.success}',
      );
    } else {
      res = await ApiService.getNearbyDrivers(
        lat: widget.pickupLat,
        lng: widget.pickupLng,
      );
    }

    if (!mounted) return;

    if (res.success) {
      final raw =
          res.data['drivers'] as List<dynamic>? ??
          res.data['data'] as List<dynamic>? ??
          (res.data.isNotEmpty ? [res.data] : <dynamic>[]);

      final parsed = raw
          .whereType<Map>()
          .map(
            (d) => _normaliseDriver(
              Map<String, dynamic>.from(d),
              userLat: widget.pickupLat,
              userLng: widget.pickupLng,
            ),
          )
          .toList();

      debugPrint(
        '📥 [DRIVERS_FETCHED] ${parsed.length} available drivers for ride',
      );

      if (isRealRide) {
        // All drivers returned by bids endpoint are available — track their IDs
        // so the vehicle-type filter (_filtered) can pass them through correctly.
        final bidsIds = parsed
            .map((d) => d['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        setState(() {
          _drivers = parsed;
          _interestedDriverIds = bidsIds;
          _loading = false;
          _fetchError = null;
        });
      } else {
        setState(() {
          _drivers = parsed;
          _loading = false;
          _fetchError = null;
        });
      }
    } else {
      debugPrint('📥 [DRIVERS_FETCH_ERROR] ${res.errorMessage}');
      if (mounted && _drivers.isEmpty) {
        setState(() {
          _drivers = [];
          _loading = false;
          _fetchError = res.errorMessage ?? context.tr('serverCacheDrivers');
        });
      }
    }
  }

  bool _doesVehicleTypeMatch(String selectedType, String driverVehicleType) {
    final sel = _mapRideTypeToEnum(selectedType);
    final drv = driverVehicleType.trim().toLowerCase();

    debugPrint(
      '🔍 [VEHICLE_MATCH] Selected: "$sel" | Driver: "$drv" | Match: ${sel == drv}',
    );

    // If driver has no vehicle type, don't show it
    if (drv.isEmpty) {
      debugPrint('⚠️ [VEHICLE_MATCH] Driver has no vehicle type - hiding');
      return false;
    }

    // Direct match (primary filter)
    if (sel == drv) return true;

    // Normalize common variations
    final selNorm = sel.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    final drvNorm = drv.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');

    if (selNorm == drvNorm) return true;

    // Specific mappings for common variations
    if (sel == 'bike') return drv.contains('bike');
    if (sel == 'auto') {
      return drv.contains('auto') && !drv.contains('sedan');
    }
    if (sel == 'ev') return drv.contains('ev');
    if (sel == 'car') return drv.contains('car') || drv.contains('sedan');
    if (sel == 'luxury') return drv.contains('luxury') || drv.contains('sedan');
    if (sel == 'suv') return drv.contains('suv');

    return false;
  }

  List<Map<String, dynamic>> get _filtered {
    debugPrint(
      '🔍 [FILTER] Total drivers: ${_drivers.length} | Selected ride type: "${widget.rideType}"',
    );

    final typeFiltered = _drivers.where((d) {
      final driverVType = d['vehicleType'] as String? ?? '';
      final matches = _doesVehicleTypeMatch(widget.rideType, driverVType);

      final driverId = d['id'] as String? ?? '';
      // For real rides: only show drivers who clicked "I'm Available" (i.e. whose
      // IDs are in the interestedDriverIds fetched from the ride document).
      // For demo rides (ride_*): show all nearby drivers matching the vehicle type.
      final isInterested = widget.rideId.startsWith('ride_')
          ? true
          : _interestedDriverIds.contains(driverId);

      final isRejected = _rejectedDriverIds.contains(driverId);

      debugPrint(
        '  → Driver: ${d['name']} | vehicleType: "$driverVType" | matches: $matches | interested: $isInterested | rejected: $isRejected',
      );
      return matches && isInterested && !isRejected;
    }).toList();

    debugPrint('✅ [FILTER] After type filter: ${typeFiltered.length} drivers');

    if (_searchQuery.isEmpty) return typeFiltered;
    final q = _searchQuery.toLowerCase();
    final searchFiltered = typeFiltered.where((d) {
      final name = (d['name'] as String? ?? '').toLowerCase();
      final vehicle = (d['vehicle'] as String? ?? '').toLowerCase();
      final vType = (d['vehicleType'] as String? ?? '').toLowerCase();
      return name.contains(q) || vehicle.contains(q) || vType.contains(q);
    }).toList();
    debugPrint(
      '✅ [FILTER] After search filter: ${searchFiltered.length} drivers',
    );
    return searchFiltered;
  }

  // ── Call driver ────────────────────────────────────────────────────────────
  Future<void> _callDriver(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('unableOpenDialer'))));
    }
  }

  // ── Assign driver ──────────────────────────────────────────────────────────
  Future<void> _showAssignSheet(Map<String, dynamic> d, _C c) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AssignConfirmSheet(driver: d, c: c),
    );

    if (result == null || result['confirmed'] != true) return;

    final fare = result['fare'] as String? ?? '';

    if (!mounted) return;
    setState(() => _assigning = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final driverId = d['id'] as String? ?? '';
    if (driverId.isEmpty) {
      setState(() => _assigning = false);
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('invalidDriver'))),
      );
      return;
    }

    final userId = await SessionService.getUserId() ?? 'guest_user';

    final distanceStr = widget.distanceKm != null
        ? '${widget.distanceKm!.toStringAsFixed(1)} km'
        : '—';
    final durationStr = widget.durationMin != null
        ? '${widget.durationMin!.toStringAsFixed(0)} mins'
        : '—';

    final ApiResponse res;
    if (widget.rideId.startsWith('ride_')) {
      res = await ApiService.assignRide(
        userId: userId,
        driverId: driverId,
        pickupLocation: widget.pickup,
        dropoffLocation: widget.destination,
        rideType: _mapRideTypeToEnum(widget.rideType),
        fare: fare,
        distance: distanceStr,
        distanceKm: widget.distanceKm,
        duration: durationStr,
        durationMin: widget.durationMin,
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
      );
    } else {
      res = await ApiService.assignRideToDriver(
        rideId: widget.rideId,
        driverId: driverId,
        fare: fare,
        distance: distanceStr,
        distanceKm: widget.distanceKm,
        duration: durationStr,
        durationMin: widget.durationMin,
      );
    }

    if (!mounted) return;
    setState(() => _assigning = false);

    final newRideId = res.success
        ? (() {
            // The backend may return the rideId at the top level or nested inside 'ride'
            final d = res.data;
            final nested = d['ride'] as Map<String, dynamic>?;
            return d['_id']?.toString() ??
                d['rideId']?.toString() ??
                d['id']?.toString() ??
                nested?['_id']?.toString() ??
                nested?['rideId']?.toString() ??
                nested?['id']?.toString() ??
                widget.rideId;
          })()
        : widget.rideId;

    debugPrint('📝 [ASSIGN_RIDE] Backend response success=${res.success}');
    debugPrint('📝 [ASSIGN_RIDE] newRideId=$newRideId, driverId=$driverId');

    if (res.success && newRideId.isNotEmpty) {
      await ActiveRideStorage.save(newRideId);
      await ApiService.syncRideRouteDetails(
        rideId: newRideId,
        distanceKm: widget.distanceKm,
        durationMin: widget.durationMin,
        distance: distanceStr,
        duration: durationStr,
        fare: fare, // ← sync fare to backend immediately after assign
      );
      RideRequestService.queueRideRequest({
        'rideId': newRideId,
        'driverId': driverId,
        'userId': userId,
        'pickup': widget.pickup,
        'destination': widget.destination,
        'rideType': widget.rideType,
        'vehicleType': _mapRideTypeToEnum(widget.rideType),
        'distance': distanceStr,
        'distanceKm': widget.distanceKm,
        'duration': durationStr,
        'durationMin': widget.durationMin,
        'fare': fare,
        'price': fare,
        'estimatedFare': fare,
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
      });
    }

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('📝 [ASSIGN_RIDE] ✅ RIDE ASSIGNED TO BACKEND');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('📝 [ASSIGN_RIDE] API Response:');
    debugPrint('   - rideId: "$newRideId"');
    debugPrint('   - driverId: "$driverId"');
    debugPrint('   - Fare: "$fare"');
    debugPrint('   - Status: assigned');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('✅ Driver will receive via backend API polling');
    debugPrint('');

    if (res.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ ${context.tr('rideAssignedSuccess')} ${d['name']}!',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (fare.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${context.tr('fareLabel')}: ₹$fare • ${context.tr('rideId')}: ${newRideId.length > 8 ? '${newRideId.substring(0, 8)}...' : newRideId}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                context.tr('driverNotifyShortly'),
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.errorMessage ?? context.tr('couldNotAssignRide')),
          backgroundColor: AppColors.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => RideConfirmationScreen(
          rideId: newRideId,
          rideType: widget.rideType,
          pickup: widget.pickup,
          destination: widget.destination,
          fare: fare,
          distanceKm: widget.distanceKm,
          durationMin: widget.durationMin,
          driver: {
            'name': d['name'] ?? '',
            'phone': d['phone'] ?? '',
            'vehicle': d['vehicleNumber'] ?? '',
            'eta': d['eta'] ?? '',
            'rating': d['rating'] ?? '',
          },
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _C(isDark);
    final list = _filtered;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        elevation: 0,
        foregroundColor: c.appBarTitle,
        iconTheme: IconThemeData(color: c.appBarTitle),
        title: Text(
          context.tr('availableDrivers'),
          style: TextStyle(
            color: c.appBarTitle,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: c.green),
            tooltip: context.tr('refresh'),
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _searchStartTime = DateTime.now();
                    });
                    _fetchDrivers();
                  },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: context.tr('searchDriverHint'),
                hintStyle: TextStyle(color: c.textSecondary, fontSize: 13),
                prefixIcon: Icon(
                  Icons.search,
                  color: c.textSecondary,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(
                          Icons.close,
                          color: c.textSecondary,
                          size: 18,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: c.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.green, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            _buildBody(c, list, isDark),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: ElevatedButton(
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
                        style: TextButton.styleFrom(foregroundColor: c.red),
                        child: Text(context.tr('yesCancel')),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  if (widget.rideId.isNotEmpty) {
                    await ApiService.cancelRide(rideId: widget.rideId);
                  }
                  await ActiveRideStorage.clear();
                  if (mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
              child: Text(
                context.tr('cancelRideBtn'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (_assigning) _buildAssigningOverlay(c),
        ],
      ),
      ),
    );
  }

  Widget _buildBody(_C c, List<Map<String, dynamic>> list, bool isDark) {
    // Loading state
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: c.green),
            const SizedBox(height: 16),
            Text(
              context.tr('fetchingDrivers'),
              style: TextStyle(color: c.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Instruction banner
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.yellow.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.yellow.withAlpha(100), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: c.dark ? c.yellow : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('callThenAssign'),
                  style: AppTextStyles.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Error / fallback banner
        if (_fetchError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentYellow.withAlpha(100)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.accentYellow,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fetchError!.split('\n').first,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: _fetchDrivers,
                  style: TextButton.styleFrom(
                    foregroundColor: c.green,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 28),
                  ),
                  child: Text(
                    context.tr('retry'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Driver count
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                '${list.length} ${context.tr(list.length == 1 ? 'driverFoundSingular' : 'driversFound')}',
                style: TextStyle(
                  fontSize: 12,
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isEmpty && !_hasSearchTimedOut) ...[
                        CircularProgressIndicator(color: c.green),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('searchingForDrivers'),
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          Icons.person_search,
                          size: 56,
                          color: c.textSecondary.withAlpha(120),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _searchQuery.isEmpty
                              ? context.tr('noDriversAvailable')
                              : context.tr('noDriversMatchSearch'),
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        if (_searchQuery.isEmpty) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () async {
                              // Re-book the ride: cancel current one, pop with 'retry'
                              if (widget.rideId.isNotEmpty && !widget.rideId.startsWith('ride_')) {
                                await ApiService.cancelRide(rideId: widget.rideId);
                              }
                              await ActiveRideStorage.clear();
                              if (mounted) {
                                Navigator.pop(context, 'retry');
                              }
                            },
                            icon: Icon(Icons.refresh, color: c.green, size: 18),
                            label: Text(
                              context.tr('tryAgain'),
                              style: TextStyle(color: c.green),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) =>
                      _DriverCard(
                        driver: list[i],
                        c: c,
                        isDark: isDark,
                        onAssign: () => _showAssignSheet(list[i], c),
                        onCall: () =>
                            _callDriver(list[i]['phone'] as String? ?? ''),
                        onChat: () {
                          // Use the ride ID from the widget so both sides
                          // share the same chat thread. If the ride hasn't
                          // been created yet (demo flow), use driver ID as
                          // a temporary thread key.
                          final chatRideId = widget.rideId.isNotEmpty
                              ? widget.rideId
                              : (list[i]['id'] as String? ?? '');
                          if (chatRideId.isEmpty || _userId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cannot open chat — ride not yet created.',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                rideId: chatRideId,
                                senderId: _userId,
                                senderModel: 'user',
                                receiverId: list[i]['id'] as String? ?? '',
                                otherPartyName:
                                    list[i]['name'] as String? ?? 'Driver',
                              ),
                            ),
                          );
                        },
                        onCancel: () async {
                          final driverId = list[i]['id'] as String? ?? '';
                          if (driverId.isEmpty) return;

                          final messenger = ScaffoldMessenger.of(context);

                          // Optimistic update
                          setState(() {
                            _rejectedDriverIds.add(driverId);
                          });

                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Driver cancelled successfully.'),
                              duration: Duration(seconds: 2),
                            ),
                          );

                          // API call in background
                          unawaited(
                            ApiService.rejectDriverBid(
                              rideId: widget.rideId,
                              driverId: driverId,
                            ),
                          );
                        },
                      ).animate().fadeIn(
                        delay: Duration(milliseconds: i * 60),
                        duration: const Duration(milliseconds: 280),
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildAssigningOverlay(_C c) {
    return Container(
      color: Colors.black.withAlpha(100),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: c.green),
              const SizedBox(height: 16),
              Text(
                context.tr('assigningDriver'),
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual driver card
// ─────────────────────────────────────────────────────────────────────────────
class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final _C c;
  final bool isDark;
  final VoidCallback onAssign;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onCancel;

  const _DriverCard({
    required this.driver,
    required this.c,
    required this.isDark,
    required this.onAssign,
    required this.onCall,
    required this.onChat,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = (driver['status'] as String? ?? '') == 'Online';
    // initials kept for accessibility semantics if needed in future

    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      color: c.card,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 40 : 8),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + info + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  // Vehicle category image (with initials fallback)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CategoryVehicleImage(
                        vehicleType: driver['vehicleType'] as String? ?? '',
                        size: 40,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.secondary
                            : AppColors.textGrey,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.card, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver['name'] as String? ?? context.tr('unknownDriver'),
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Show vehicle number (the main identifier from the DB)
                    Row(
                      children: [
                        CategoryVehicleImage(
                          vehicleType: driver['vehicleType'] as String? ?? '',
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (driver['vehicleNumber'] as String?)?.isNotEmpty ==
                                  true
                              ? driver['vehicleNumber'] as String
                              : context.tr('noVehicleInfo'),
                          style: AppTextStyles.body.copyWith(
                            fontSize: 11,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Phone number
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 11,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          driver['phone'] as String? ?? '',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 11,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.secondary.withAlpha(30)
                      : AppColors.textGrey.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOnline
                        ? AppColors.secondary.withAlpha(120)
                        : AppColors.textGrey.withAlpha(80),
                  ),
                ),
                child: Text(
                  isOnline ? context.tr('online') : context.tr('offline'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isOnline ? AppColors.secondary : AppColors.textGrey,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 6),

          // Chips — only show fields that actually come from the DB
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if ((driver['vehicleNumber'] as String?)?.isNotEmpty == true)
                _chip(
                  c,
                  Icons.confirmation_number_outlined,
                  driver['vehicleNumber'] as String,
                ),
              if ((driver['distanceKm'] as String?) != '—' &&
                  (driver['distanceKm'] as String?)?.isNotEmpty == true)
                _chip(
                  c,
                  Icons.near_me_outlined,
                  '${driver['distanceKm']} ${context.tr('kmAway')}',
                ),
              if ((driver['eta'] as String?) != '—' &&
                  (driver['eta'] as String?)?.isNotEmpty == true)
                _chip(
                  c,
                  Icons.access_time_outlined,
                  driver['eta'] as String,
                  iconColor: AppColors.accentYellow,
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Call button
              GestureDetector(
                onTap: onCall,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.green.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.green.withAlpha(120), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_rounded, color: c.green, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('call'),
                        style: TextStyle(
                          color: c.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Cancel button
              GestureDetector(
                onTap: onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accentRed.withAlpha(120),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cancel_outlined,
                        color: AppColors.accentRed,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('cancel'),
                        style: const TextStyle(
                          color: AppColors.accentRed,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Chat button
              GestureDetector(
                onTap: onChat,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentStrong.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accentStrong.withAlpha(120),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: AppColors.accentStrong,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Chat',
                        style: TextStyle(
                          color: AppColors.accentStrong,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Assign button
              GestureDetector(
                onTap: onAssign,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.green,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: c.green.withAlpha(80),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('assign'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(_C c, IconData icon, String label, {Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: c.cardSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor ?? c.green),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assign confirmation bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _AssignConfirmSheet extends StatefulWidget {
  final Map<String, dynamic> driver;
  final _C c;

  const _AssignConfirmSheet({required this.driver, required this.c});

  @override
  State<_AssignConfirmSheet> createState() => _AssignConfirmSheetState();
}

class _AssignConfirmSheetState extends State<_AssignConfirmSheet> {
  final TextEditingController _fareCtrl = TextEditingController();
  bool _isFareValid = false;

  @override
  void initState() {
    super.initState();
    _fareCtrl.addListener(_validateFare);
  }

  void _validateFare() {
    setState(() {
      _isFareValid = _fareCtrl.text.trim().isNotEmpty;
    });
  }

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.driver['name'] as String? ?? 'Driver';
    final vNum = widget.driver['vehicleNumber'] as String? ?? '';
    final phone = widget.driver['phone'] as String? ?? '';
    final initials = name
        .split(' ')
        .map((s) => s.isNotEmpty ? s[0] : '')
        .take(2)
        .join();

    return Container(
      decoration: BoxDecoration(
        color: widget.c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.c.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 36,
              backgroundColor: widget.c.green,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('assignRideTo'),
              style: TextStyle(
                fontSize: 14,
                color: widget.c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 22,
                color: widget.c.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$vNum  •  $phone',
              style: TextStyle(fontSize: 13, color: widget.c.textSecondary),
            ),
            const SizedBox(height: 20),
            // ── Fare input field (REQUIRED) ────────────────────────────────────
            TextField(
              controller: _fareCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: widget.c.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: context.tr('enterFareHint'),
                hintStyle: TextStyle(
                  color: widget.c.textSecondary,
                  fontSize: 14,
                ),
                labelText: context.tr('fareAmountRequired'),
                labelStyle: TextStyle(
                  color: widget.c.green,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(
                  Icons.local_atm,
                  color: widget.c.green,
                  size: 20,
                ),
                filled: true,
                fillColor: widget.c.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _isFareValid ? widget.c.green : widget.c.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.c.green, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.accentRed,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('fareDiscussNote'),
              style: TextStyle(
                fontSize: 12,
                color: widget.c.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accentYellow.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accentYellow.withAlpha(100),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: AppColors.accentYellow,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('driverNotifyFare'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.c.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.c.textSecondary,
                      side: BorderSide(color: widget.c.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      context.tr('cancel'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isFareValid
                        ? () => Navigator.pop(context, {
                            'confirmed': true,
                            'fare': _fareCtrl.text.trim(),
                          })
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFareValid
                          ? widget.c.green
                          : widget.c.border,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _isFareValid
                          ? context.tr('confirmAssignment')
                          : context.tr('enterFareFirst'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
