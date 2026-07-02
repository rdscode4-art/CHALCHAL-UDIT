import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/ride.dart';
import '../../../core/services/active_ride_storage.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/ride_status.dart';
import '../../../core/services/socket_service.dart';

import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/glass_card.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import 'user_ride_progress_screen.dart';
import '../../../core/localization/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Centralised theme-aware colour resolver — same pattern as SelectRideScreen
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  final bool dark;
  const _C(this.dark);

  Color get scaffold => dark ? AppColors.darkBackground : AppColors.background;
  Color get surface => dark ? AppColors.darkSurface : AppColors.surface;
  Color get surfaceSoft =>
      dark ? AppColors.darkSurfaceSoft : AppColors.surfaceLight;
  Color get surfaceVariant =>
      dark ? AppColors.darkSurfaceVariant : AppColors.surfaceSoft;
  Color get border => dark ? AppColors.darkBorder : AppColors.border;
  Color get textPrimary => dark ? AppColors.darkOnSurface : AppColors.textDark;
  Color get textSecondary => dark
      ? AppColors.darkOnSurface.withValues(alpha: 0.60)
      : AppColors.textGrey;
  Color get textMuted => dark
      ? AppColors.darkOnSurface.withValues(alpha: 0.45)
      : AppColors.textDark.withValues(alpha: 0.50);

  Color get green => AppColors.accentStrong;
  Color get yellow => AppColors.accentYellow;
  Color get red => AppColors.accentRed;

  // Timeline step dot
  Color get stepActive => green;
  Color get stepInactive =>
      dark ? AppColors.darkSurfaceVariant : AppColors.surfaceLight;
  Color get stepLine => dark ? AppColors.darkBorder : AppColors.border;

  // Tip button
  Color get tipSelected => green;
  Color get tipUnselected => surfaceSoft;
  Color get tipBorderSel => green;
  Color get tipBorderUnsel => green.withValues(alpha: 0.20);
}

// ─────────────────────────────────────────────────────────────────────────────
class RideConfirmationScreen extends StatefulWidget {
  final String rideId;
  final String rideType;
  final String pickup;
  final String destination;
  final Map<String, String>? driver;

  /// The fare agreed by the user before assigning the ride. Used as a fallback
  /// if the backend hasn't stored/returned the fare yet during polling.
  final String? fare;
  final double? distanceKm;
  final double? durationMin;

  const RideConfirmationScreen({
    super.key,
    required this.rideId,
    required this.rideType,
    required this.pickup,
    required this.destination,
    this.driver,
    this.fare,
    this.distanceKm,
    this.durationMin,
  });

  @override
  State<RideConfirmationScreen> createState() => _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends State<RideConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _carController;

  int _currentTripStep = 0;
  bool _rideCompleted = false;
  int _selectedRating = 5;
  Ride? _ride;
  String? _rideFetchError;
  Timer? _pollTimer;
  Map<String, String>? _polledDriver;
  bool _waitingForDriver = true;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  bool _navigatedToProgress = false;
  Map<String, dynamic> _rideRaw = {};
  bool _submittingReview = false;

  final TextEditingController _feedbackController = TextEditingController();

  final List<Map<String, String>> _tripProgressSteps = [
    {'title': 'Ride assigned', 'subtitle': 'Driver has been notified.'},
    {'title': 'Driver accepted', 'subtitle': 'Driver will arrive soon.'},
    {'title': 'Arriving', 'subtitle': 'Driver is on the way.'},
    {'title': 'Ride completed', 'subtitle': 'Please rate your experience.'},
  ];

  @override
  void initState() {
    super.initState();
    _carController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    ActiveRideStorage.save(widget.rideId);
    
    // Connect to socket and listen for real-time status updates (e.g. driver declination/acceptance)
    SocketService().connect();
    SocketService().joinRide(widget.rideId);
    SocketService().onStatusUpdated((status) {
      debugPrint('🔔 [SOCKET] Status update in confirmation: $status');
      if (!mounted) return;
      _pollRideStatus();
    });

    // Fetch ride details immediately on load
    _pollRideStatus();
    _startPolling();

    // Listen for FCM push if driver rejects the ride
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      final data = message.data;
      final event = data['event'];
      final msgRideId = data['rideId'];
      if (msgRideId == widget.rideId && event == 'ride_rejected') {
        debugPrint('🚫 [FCM] ride_rejected received in RideConfirmation! Reverting to bidding screen.');
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
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollRideStatus();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollRideStatus(),
    );
  }

  void _goToProgressScreen() {
    if (_navigatedToProgress || !mounted) return;
    _navigatedToProgress = true;
    _stopPolling();

    // Delay slightly to ensure confirmation screen is visible before transition
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      // Replace current route with progress screen instead of popping all
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UserRideProgressScreen(
            rideId: widget.rideId,
            pickup: widget.pickup,
            destination: widget.destination,
            rideType: widget.rideType,
            driver: _effectiveDriver,
            ride: _ride,
            distanceKm: widget.distanceKm,
            durationMin: widget.durationMin,
            rideData: {
              if (_rideRaw.isNotEmpty) ..._rideRaw,
              if (widget.fare != null && widget.fare!.isNotEmpty)
                'fare': widget.fare,
              if (widget.distanceKm != null) 'distanceKm': widget.distanceKm,
              if (widget.durationMin != null) 'durationMin': widget.durationMin,
              if (widget.distanceKm != null)
                'distance': '${widget.distanceKm!.toStringAsFixed(1)} km',
              if (widget.durationMin != null)
                'duration': '${widget.durationMin!.round()} mins',
            },
          ),
        ),
      );
    });
  }

  Map<String, String>? _driverFromPayload(Map<String, dynamic> rideMap) {
    final driver = rideMap['driver'];
    if (driver is Map) {
      final m = Map<String, dynamic>.from(driver);
      final map = {
        if (m['name'] != null) 'name': m['name'].toString(),
        if (m['phone'] != null) 'phone': m['phone'].toString(),
        if (m['vehicleNumber'] != null)
          'vehicle': m['vehicleNumber'].toString(),
        if (m['vehicle'] != null) 'vehicle': m['vehicle'].toString(),
        if (m['rating'] != null) 'rating': m['rating'].toString(),
        if (m['eta'] != null) 'eta': m['eta'].toString(),
      };
      if (map.isNotEmpty) return map;
    }
    final name = rideMap['driverName']?.toString();
    final phone = rideMap['driverPhone']?.toString();
    if (name != null && name.isNotEmpty) {
      return {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (rideMap['vehicleNumber'] != null)
          'vehicle': rideMap['vehicleNumber'].toString(),
      };
    }
    return null;
  }

  Future<void> _pollRideStatus() async {
    if (!mounted || widget.rideId.isEmpty) return;

    try {
      debugPrint('🔄 [POLL] Fetching ride details for ID: ${widget.rideId}');
      final res = await ApiService.getRide(widget.rideId);
      if (!mounted) return;

      debugPrint(
        '📥 [POLL] Response Success: ${res.success}, Status Code: ${res.statusCode}',
      );

      if (res.statusCode == 404) {
        debugPrint('❌ [POLL] Ride not found (404)');
        _stopPolling();
        await ActiveRideStorage.clear();
        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
        return;
      }

      if (!res.success) {
        final errorMsg = res.statusCode != null && res.statusCode! >= 500
            ? 'Connection error, retrying...'
            : (res.errorMessage ?? 'No internet connection');
        debugPrint('⚠️ [POLL] API Error: $errorMsg');
        setState(() {
          _rideFetchError = errorMsg;
        });
        return;
      }

      final rideMap = Map<String, dynamic>.from(res.data);
      final status = RideStatus.resolveEffectiveStatus(
        rideMap,
        rideMap['status']?.toString() ?? '',
      );
      rideMap['status'] = status;

      debugPrint(
        '🔍 [RAW_RIDE_DATA] Full response keys: ${rideMap.keys.toList()}',
      );
      debugPrint(
        '🔍 [RAW_RIDE_DATA] Ride ID: ${rideMap['id'] ?? rideMap['rideId']}',
      );
      debugPrint('🔍 [RAW_RIDE_DATA] Driver: ${rideMap['driver']}');
      debugPrint('🔍 [RAW_RIDE_DATA] Fare: ${rideMap['fare']}');
      debugPrint('📊 [USER_POLL] GET /rides/${widget.rideId} → $status');

      if (status == 'declined' || status == 'rejected') {
        debugPrint('❌ [POLL] Ride declined/rejected');
        _stopPolling();
        await ActiveRideStorage.clear();
        setState(() {
          _ride = Ride.fromJson(rideMap);
          _rideFetchError = null;
          _waitingForDriver = false;
          _rideCompleted = false;
        });
        return;
      }

      if (status == 'cancelled' || status == 'canceled') {
        debugPrint('❌ [POLL] Ride cancelled');
        _stopPolling();
        await ActiveRideStorage.clear();
        setState(() {
          _ride = Ride.fromJson(rideMap);
          _waitingForDriver = false;
          _rideFetchError = null;
          _rideCompleted = false;
        });
        return;
      }

      final ride = Ride.fromJson(rideMap);
      final driverMap = _driverFromPayload(rideMap);

      debugPrint(
        '✅ [POLL] Ride status: $status, Driver: ${driverMap?['name'] ?? 'N/A'}',
      );

      setState(() {
        _ride = ride;
        _rideRaw = rideMap;
        _rideFetchError = null;
        _polledDriver = driverMap ?? widget.driver;
        _waitingForDriver =
            RideStatus.isPending(status) && !RideStatus.isAccepted(status);
        _currentTripStep = _tripStepFromStatus(status);
        _rideCompleted = RideStatus.isCompleted(status);
      });

      if (RideStatus.isAccepted(status)) {
        debugPrint('✅ [POLL] Ride accepted, navigating to progress screen');
        _goToProgressScreen();
        return;
      }
      if (RideStatus.isOngoing(status)) {
        debugPrint('✅ [POLL] Ride ongoing, navigating to progress screen');
        _goToProgressScreen();
        return;
      }
      if (status == 'completed' || ride.isCompleted) {
        debugPrint('✅ [POLL] Ride completed, navigating to progress screen');
        _stopPolling();
        _goToProgressScreen();
        return;
      }
    } catch (e) {
      debugPrint('❌ [USER_POLL] Polling error: $e');
      if (mounted) {
        setState(() => _rideFetchError = 'No internet connection');
      }
    }
  }

  int _tripStepFromStatus(String status) {
    final s = RideStatus.normalize(status);

    if (RideStatus.isPending(s)) return 0;
    if (RideStatus.isAccepted(s)) return 1;
    if (RideStatus.isOngoing(s)) return 2;
    if (RideStatus.isCompleted(s)) return 3;

    return _currentTripStep;
  }

  String _formatStatusForDisplay(Ride ride) {
    if (ride.isDeclined) {
      return 'Driver declined — select another driver';
    }
    if (ride.isCancelled) return 'Ride cancelled';
    if (ride.isCompleted) return 'Ride completed';
    if (ride.isOngoing) return 'Your ride has started';
    if (ride.isAccepted) return 'Driver accepted your ride';
    if (ride.isPendingAssignment) return 'Waiting for driver to accept';

    final s = RideStatus.normalize(ride.status);
    return s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : 'Updating…';
  }

  Widget _buildLiveStatusBanner(_C c) {
    if (_ride == null) return const SizedBox.shrink();

    final ride = _ride!;
    IconData icon;
    Color color;
    String title;
    String subtitle;

    final status = RideStatus.normalize(ride.status);

    if (status == 'ongoing' || ride.isOngoing) {
      icon = Icons.directions_car_filled;
      color = c.green;
      title = 'Ride in progress';
      subtitle = 'Ride in progress...';
    } else if (status == 'accepted' || ride.isAccepted) {
      icon = Icons.check_circle_outline;
      color = c.green;
      title = 'Driver accepted';
      subtitle = 'Driver accepted! On the way 🚗';
    } else if (status == 'pending' ||
        status == 'assigned' ||
        ride.isPendingAssignment) {
      icon = Icons.hourglass_top_rounded;
      color = c.yellow;
      title = 'Looking for driver';
      subtitle = 'Looking for driver...';
    } else if (ride.isDeclined || ride.isCancelled) {
      icon = Icons.cancel_outlined;
      color = c.red;
      title = ride.isDeclined ? 'Driver declined' : 'Ride cancelled';
      subtitle = _formatStatusForDisplay(ride);
    } else if (ride.isCompleted) {
      icon = Icons.flag_outlined;
      color = c.green;
      title = 'Ride completed';
      subtitle = 'Thank you for riding with us.';
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 16,
                      color: c.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String>? get _effectiveDriver {
    if (_polledDriver != null && _polledDriver!.isNotEmpty) {
      return _polledDriver;
    }
    final fromRide = _ride?.driver;
    if (fromRide != null && fromRide.isNotEmpty) return fromRide;
    return widget.driver;
  }

  bool _isDriverMatchingRideType() {
    final driver = _effectiveDriver;
    if (driver == null) return false;

    final driverVehicleType =
        driver['vehicleType']?.toLowerCase() ??
        driver['vehicle']?.toLowerCase() ??
        '';
    final selectedRideType = widget.rideType.toLowerCase();

    // Check if driver's vehicle type contains or matches the selected ride type
    return driverVehicleType.contains(selectedRideType) ||
        selectedRideType.contains(driverVehicleType);
  }

  @override
  void dispose() {
    _carController.dispose();
    _stopPolling();
    _fcmSubscription?.cancel();
    _feedbackController.dispose();
    SocketService().removeAllListeners();
    super.dispose();
  }

  // ── Rating star ────────────────────────────────────────────────────────────
  Widget _buildRatingStar(_C c, int value) {
    final selected = value <= _selectedRating;
    return GestureDetector(
      onTap: () => setState(() => _selectedRating = value),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        scale: selected ? 1.15 : 1.0,
        child: Icon(
          selected ? Icons.star : Icons.star_border,
          color: selected ? c.yellow : c.textSecondary,
          size: 34,
        ),
      ),
    );
  }

  // ── Trip progress timeline ─────────────────────────────────────────────────
  Widget _buildTripProgressTimeline(_C c) {
    return GlassCard(
      borderRadius: BorderRadius.circular(24),
      color: c.surface,
      border: Border.all(color: c.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('tripProgress'),
            style: AppTextStyles.heading.copyWith(
              fontSize: 18,
              color: c.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: List.generate(_tripProgressSteps.length, (index) {
              final step = _tripProgressSteps[index];
              final completed = index < _currentTripStep;
              final active = index == _currentTripStep;
              final isLast = index == _tripProgressSteps.length - 1;

              final String rawTitle = step['title']!;
              final String rawSubtitle = step['subtitle']!;
              String titleText = rawTitle;
              String subtitleText = rawSubtitle;
              if (rawTitle == 'Ride assigned') {
                titleText = context.tr('rideAssigned');
                subtitleText = context.tr('driverNotified');
              } else if (rawTitle == 'Driver accepted') {
                titleText = context.tr('driverAccepted');
                subtitleText = context.tr('driverArriveSoon');
              } else if (rawTitle == 'Arriving') {
                titleText = context.tr('arriving');
                subtitleText = context.tr('driverOnWay');
              } else if (rawTitle == 'Ride completed') {
                titleText = context.tr('rideCompleted');
                subtitleText = context.tr('rateExperience');
              }

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
                                  ? c.stepActive
                                  : c.stepInactive,
                              borderRadius: BorderRadius.circular(8),
                              border: active
                                  ? Border.all(color: c.green, width: 2)
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
                              color: completed ? c.stepActive : c.stepLine,
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
                                titleText,
                                style: AppTextStyles.cardTitle.copyWith(
                                  fontSize: 14,
                                  color: (completed || active)
                                      ? c.textPrimary
                                      : c.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitleText,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 13,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast) const SizedBox(height: 16),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Review section ─────────────────────────────────────────────────────────
  Widget _buildReviewSection(_C c) {
    return GlassCard(
      borderRadius: BorderRadius.circular(24),
      color: c.surface,
      border: Border.all(color: c.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('rideComplete'),
            style: AppTextStyles.heading.copyWith(
              fontSize: 20,
              color: c.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('rateDriverFeedback'),
            style: AppTextStyles.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) => _buildRatingStar(c, i + 1)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _feedbackController,
            maxLines: 4,
            style: AppTextStyles.body.copyWith(color: c.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.surfaceSoft,
              hintText: context.tr('shareExperience'),
              hintStyle: AppTextStyles.body.copyWith(color: c.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: c.green, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            label: _submittingReview
                ? context.tr('submitting')
                : context.tr('submitReview'),
            color: c.green,
            onPressed: _submittingReview
                ? () {}
                : () async {
                    setState(() => _submittingReview = true);
                    final res = await ApiService.rateRide(
                      rideId: widget.rideId,
                      rating: _selectedRating,
                      ratingComment: _feedbackController.text.trim(),
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
                      Navigator.popUntil(context, (route) => route.isFirst);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to submit review: ${res.errorMessage}',
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

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _C(isDark);

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        title: Text(
          _ride?.isAccepted == true || _ride?.isOngoing == true || _ride?.isCompleted == true
              ? context.tr('rideConfirmed')
              : (context.tr('waitingForDriverAccept') ?? 'Waiting for Driver...'),
          style: AppTextStyles.heading.copyWith(
            fontSize: 18,
            color: c.textPrimary,
          ),
        ),
        backgroundColor: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            if (_ride == null && _rideFetchError == null) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: c.green),
                      const SizedBox(height: 16),
                      Text(
                        _waitingForDriver
                            ? context.tr('waitingForDriverAccept')
                            : 'Updating...',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CustomButton(
                        label: context.tr('cancelRide'),
                        color: c.red,
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);

                          // Show confirmation dialog
                          final confirmed = await showDialog<bool>(
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

                          if (confirmed != true || !mounted) return;

                          _stopPolling();

                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Cancelling ride...'),
                              duration: Duration(seconds: 5),
                            ),
                          );

                          final cancelRes = await ApiService.cancelRideByUser(
                            rideId: widget.rideId,
                          );

                          if (!mounted) return;

                          if (cancelRes.success) {
                            await ActiveRideStorage.clear();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Ride cancelled successfully.'),
                                backgroundColor: AppColors.secondary,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            await Future.delayed(const Duration(seconds: 1));
                            if (mounted) {
                              navigator.popUntil((r) => r.isFirst);
                            }
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to cancel: ${cancelRes.errorMessage}',
                                ),
                                backgroundColor: AppColors.accentRed,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                            _startPolling();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_ride != null) ...[
              _buildLiveStatusBanner(c),
            ] else if (_rideFetchError != null) ...[
              Text(
                _rideFetchError!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: c.red),
              ),
              const SizedBox(height: 8),
              CustomButton(
                label: context.tr('retry'),
                color: c.green,
                onPressed: () {
                  _stopPolling();
                  _startPolling();
                },
              ),
              const SizedBox(height: 8),
            ],

            // ── Driver card ────────────────────────────────────────────────
            if (_effectiveDriver != null &&
                _effectiveDriver!.isNotEmpty &&
                _isDriverMatchingRideType()) ...[
              GlassCard(
                borderRadius: BorderRadius.circular(18),
                color: c.surface,
                padding: const EdgeInsets.all(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: c.green,
                      child: Text(
                        (_effectiveDriver?['name'] ?? '')
                            .split(' ')
                            .map((s) => s.isNotEmpty ? s[0] : '')
                            .take(2)
                            .join(),
                        style: AppTextStyles.heading.copyWith(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _effectiveDriver?['name'] ?? 'Driver',
                            style: AppTextStyles.heading.copyWith(
                              fontSize: 16,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_effectiveDriver?['vehicle'] ?? 'N/A'}  •  ⭐ ${_effectiveDriver?['rating'] ?? '—'}',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                          if ((_effectiveDriver?['phone'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _effectiveDriver?['phone'] ?? '',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // ETA chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.green.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        _effectiveDriver?['eta'] ?? '',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12,
                          color: c.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 20),

            // ── Trip details (Pickup, Destination, Fare, Distance, Payment) ──
            GlassCard(
              borderRadius: BorderRadius.circular(18),
              color: c.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: c.green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Trip Details',
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: 14,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Pickup
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentStrong,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pickup',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.pickup,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: c.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Destination
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentRed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destination',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.destination,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: c.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: c.border),
                  const SizedBox(height: 16),
                  // Fare and Distance - Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Fare
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fare',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              () {
                                final f = _ride?.fare;
                                final rawF = _rideRaw['fare'];
                                // Prefer polled fare, then ride fare, then rideRaw fare, then widget.fare
                                final fareNum = rawF is num
                                    ? rawF
                                    : num.tryParse(rawF?.toString() ?? '');
                                final rideNum = f is num
                                    ? f
                                    : num.tryParse(f?.toString() ?? '');
                                final widgetFareNum = num.tryParse(
                                  widget.fare ?? '',
                                );
                                final best = (fareNum != null && fareNum > 0)
                                    ? fareNum
                                    : (rideNum != null && rideNum > 0)
                                    ? rideNum
                                    : (widgetFareNum != null &&
                                          widgetFareNum > 0)
                                    ? widgetFareNum
                                    : null;
                                if (best == null) return '—';
                                return '₹${best.toStringAsFixed(best.truncateToDouble() == best ? 0 : 2)}';
                              }(),
                              style: AppTextStyles.heading.copyWith(
                                fontSize: 16,
                                color: c.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Distance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distance',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _rideRaw['distance'] != null
                                  ? '${_rideRaw['distance']} km'
                                  : '—',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Ride Type with category image
                  if (widget.rideType.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        CategoryVehicleImage(
                          vehicleType: widget.rideType,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.rideType,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              color: c.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Trip progress ──────────────────────────────────────────────
            _buildTripProgressTimeline(c),
            const SizedBox(height: 20),

            // ── Action buttons / review ────────────────────────────────────
            if (_ride?.isDeclined == true) ...[
              CustomButton(
                label: context.tr('pleaseBookAgain'),
                color: c.green,
                onPressed: () async {
                  await ActiveRideStorage.clear();
                  if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
                },
              ),
              const SizedBox(height: 12),
            ] else if (_rideCompleted && _ride?.isCompleted == true) ...[
              _buildReviewSection(c),
            ] else if (!_rideCompleted &&
                (_ride == null || !_ride!.isCompleted)) ...[
              CustomButton(
                label: context.tr('cancelRide'),
                color: c.red,
                onPressed: () async {
                  // Show confirmation dialog
                  final confirmed = await showDialog<bool>(
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

                  if (confirmed != true || !mounted) return;

                  _stopPolling();

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cancelling ride...'),
                      duration: Duration(seconds: 5),
                    ),
                  );

                  final cancelRes = await ApiService.cancelRideByUser(
                    rideId: widget.rideId,
                  );

                  if (!mounted) return;

                  if (cancelRes.success) {
                    await ActiveRideStorage.clear();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ride cancelled successfully.'),
                        backgroundColor: AppColors.secondary,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    await Future.delayed(const Duration(seconds: 1));
                    if (mounted) {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    }
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to cancel: ${cancelRes.errorMessage}',
                        ),
                        backgroundColor: AppColors.accentRed,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    _startPolling();
                  }
                },
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
