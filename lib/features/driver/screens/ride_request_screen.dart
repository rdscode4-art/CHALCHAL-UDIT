import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/chat_screen.dart';
import 'driver_active_ride_screen.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/firebase_notification_service.dart';

class RideRequestScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String destination;
  final String distance;
  final String rideType;
  final String duration;
  final String? fare;

  /// When true the user has already assigned this driver — the button says
  /// "Accept Ride" and clicking it goes straight to the active ride.
  final bool isAssigned;

  const RideRequestScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.destination,
    required this.distance,
    required this.rideType,
    required this.duration,
    this.fare,
    this.isAssigned = false,
  });

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  int _countdown = 30;
  Timer? _timer;
  bool _accepting = false;
  String? _acceptError;
  Map<String, dynamic>? _currentRideData;
  String _passengerName = '';
  String _passengerPhone = '—';
  late String _distance;
  late String _duration;
  String _driverId = '';

  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    _distance = widget.distance;
    _duration = widget.duration;
    debugPrint('🎫 RideRequestScreen initialized:');
    debugPrint('   Ride ID: ${widget.rideId}');
    debugPrint('   Pickup: ${widget.pickup}');
    debugPrint('   Destination: ${widget.destination}');
    debugPrint('   Distance: ${widget.distance}');
    debugPrint('   Duration: ${widget.duration}');
    debugPrint('   Ride Type: ${widget.rideType}');
    debugPrint('   Fare: ${widget.fare ?? "NOT SET"}');
    _startCountdown();
    _fetchRideDetails();
    _playRequestSound();
    // Load driver ID for chat
    SessionService.getDriverId().then((id) {
      if (mounted && id != null && id.isNotEmpty) {
        setState(() => _driverId = id);
      }
    });

    // Listen for ride cancellation push
    FirebaseNotificationService().onRideCancelled = (cancelledRideId) {
      if (mounted && cancelledRideId == widget.rideId) {
        debugPrint('🔔 [RideRequestScreen] Ride cancelled via push! Stopping sound.');
        _audioPlayer?.stop();
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    };
  }

  Future<void> _playRequestSound() async {
    try {
      _audioPlayer = AudioPlayer();
      // audioplayers v6: configure audio context for ringtone-style playback
      // so it plays over silent/DND modes and requests audio focus correctly
      await _audioPlayer!.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer!.setVolume(1.0);
      await _audioPlayer!.play(AssetSource('audio/request_sound.mp3'));
      debugPrint('🔔 [SOUND] Request sound playing');
    } catch (e) {
      debugPrint('Error playing ride request sound: $e');
    }
  }

  Future<void> _fetchRideDetails() async {
    if (widget.rideId.isEmpty) return;
    try {
      final res = await ApiService.getRide(widget.rideId);
      if (res.success && res.data.isNotEmpty && mounted) {
        final data = ApiService.unwrapRidePayload(res.data);
        
        // Auto-close if ride is already cancelled or completed
        final status = data['status']?.toString().toLowerCase() ?? '';
        if (status == 'cancelled' || status == 'completed') {
          debugPrint('🚫 [RideRequestScreen] Ride is already $status! Auto-closing.');
          _audioPlayer?.stop();
          if (Navigator.canPop(context)) {
            Navigator.pop(context, 'ignored');
          }
          return;
        }

        final distance = ApiService.formatDistanceDisplay(
          data['distance'] ?? data['distanceKm'],
        );
        final duration = ApiService.formatDurationDisplay(
          data['duration'] ?? data['durationMin'],
        );
        // Resolve fare from backend if not already passed in
        final fareNum = ApiService.resolveRideFare(data);
        setState(() {
          _passengerName =
              data['passengerName']?.toString() ??
              data['riderName']?.toString() ??
              '';
          _passengerPhone =
              data['passengerPhone']?.toString() ??
              data['riderPhone']?.toString() ??
              '—';
          if (distance != '—') _distance = distance;
          if (duration != '—') _duration = duration;
          // Store full ride data for fare display fallback
          _currentRideData = data;
          // If fare wasn't passed as widget param, update from API
          if ((widget.fare == null || widget.fare!.isEmpty) &&
              fareNum != null) {
            _currentRideData!['fare'] = fareNum.toString();
          }
        });
        debugPrint('📦 [RIDE_REQUEST] Route from API: $_distance / $_duration');
        debugPrint(
          '📦 [RIDE_REQUEST] Fare from API: ${fareNum ?? widget.fare ?? "N/A"}',
        );
      }
    } catch (_) {}
  }

  void _startCountdown() {
    _timer?.cancel(); // cancel any existing timer before starting a new one
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        if (mounted) Navigator.pop(context);
      }
    });
  }

  Future<void> _accept() async {
    if (_accepting) return;

    _timer?.cancel();
    setState(() {
      _accepting = true;
      _acceptError = null;
    });

    // ── Assigned path: user already chose us — just confirm ──────────────
    if (widget.isAssigned) {
      debugPrint('✅ [ACCEPT] Driver accepting assigned ride ${widget.rideId}');
      if (mounted) {
        setState(() => _accepting = false);
        _audioPlayer?.stop();
        Navigator.pop(context, 'accepted');
      }
      return;
    }

    // ── Interest path: declare availability to the user ──────────────────
    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) {
      setState(
        () => _acceptError = 'Driver session not found. Please log in again.',
      );
      _startCountdown();
      setState(() => _accepting = false);
      return;
    }

    if (widget.rideId.isEmpty) {
      setState(
        () => _acceptError = 'Ride id missing. Cannot express interest.',
      );
      _startCountdown();
      setState(() => _accepting = false);
      return;
    }

    debugPrint(
      '🚗 [INTERESTED] Declaring driver available for rideId=${widget.rideId}',
    );

    // If local demo ride, pop immediately
    if (widget.rideId.startsWith('ride_')) {
      if (mounted) {
        setState(() => _accepting = false);
        Navigator.pop(context, widget.isAssigned ? 'accepted' : 'interested');
      }
      return;
    }

    if (widget.isAssigned) {
      if (mounted) {
        _audioPlayer?.stop();
        setState(() => _accepting = false);
        Navigator.pop(context, 'accepted');
      }
      return;
    }

    bool success = false;
    try {
      final res = await ApiService.declareDriverAvailable(
        rideId: widget.rideId,
        driverId: driverId,
      );
      success = res.success;
      if (!success) {
        _acceptError = res.errorMessage;
      }
    } catch (e) {
      debugPrint('Error declaring availability: $e');
      _acceptError = e.toString();
    }

    if (!mounted) return;

    setState(() => _accepting = false);

    if (success) {
      _audioPlayer?.stop();
      Navigator.pop(context, 'interested');
    } else {
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_acceptError ?? 'Failed to declare availability'),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _decline() {
    _timer?.cancel();
    _audioPlayer?.stop();
    Navigator.pop(context, 'declined');
  }

  void _cancel() {
    _timer?.cancel();
    _audioPlayer?.stop();
    Navigator.pop(context, 'cancelled');
  }

  void _navigateToActiveRide() {
    final d = _currentRideData ?? {};
    final rideId =
        d['rideId']?.toString() ??
        d['_id']?.toString() ??
        d['id']?.toString() ??
        widget.rideId;
    final pickup =
        d['pickup']?.toString() ??
        d['pickupLocation']?.toString() ??
        widget.pickup;
    final destination =
        d['destination']?.toString() ??
        d['dropoffLocation']?.toString() ??
        d['dropoff']?.toString() ??
        widget.destination;
    final rideType =
        d['rideType']?.toString() ??
        d['vehicleType']?.toString() ??
        widget.rideType;
    final distance = ApiService.formatDistanceDisplay(
      d['distance'] ?? d['distanceKm'],
    );
    final duration = ApiService.formatDurationDisplay(
      d['duration'] ?? d['durationMin'],
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverActiveRideScreen(
          rideId: rideId,
          pickup: pickup,
          destination: destination,
          rideType: rideType,
          distance: distance != '—' ? distance : _distance,
          duration: duration != '—' ? duration : _duration,
          fare:
              widget.fare ??
              _currentRideData?['fare']?.toString(), // pass fare through
        ),
      ),
    ).then((result) {
      // If result is true, the ride was completed successfully
      // Pop back to driver home with the completion result
      debugPrint(
        '🏁 [RIDE_COMPLETE] Returned from active ride with result: $result',
      );

      if (mounted) {
        // Return the result to driver home screen
        Navigator.of(context).pop(result == true ? 'completed' : result);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    FirebaseNotificationService().onRideCancelled = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final bgAlt = isDark ? AppColors.darkSurface : AppColors.surfaceSoft;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _rideRequestView(isDark, bgAlt),
        ),
      ),
    );
  }

  Widget _rideRequestView(bool isDark, Color cardBg) {
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.6)
        : AppColors.textGrey;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Countdown ring
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: _countdown / 30,
                  strokeWidth: 6,
                  color: widget.isAssigned
                      ? AppColors.secondary
                      : (_countdown > 10
                            ? AppColors.accentStrong
                            : AppColors.accentRed),
                  backgroundColor: borderColor,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_countdown',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: widget.isAssigned
                          ? AppColors.secondary
                          : (_countdown > 10
                                ? AppColors.accentStrong
                                : AppColors.accentRed),
                    ),
                  ),
                  Text(
                    context.tr('sec'),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            widget.isAssigned
                ? '🎉 Ride Assigned to You!'
                : context.tr('newRideRequest'),
            style: AppTextStyles.heading.copyWith(
              fontSize: 22,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            widget.isAssigned
                ? 'The passenger has chosen you. Accept to start the ride.'
                : context.tr('acceptBeforeTimer'),
            style: AppTextStyles.body.copyWith(fontSize: 13, color: subColor),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),

        // Trip card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _tripRow(
                    Icons.my_location_outlined,
                    AppColors.accentStrong,
                    context.tr('pickup'),
                    widget.pickup,
                    textColor,
                    subColor,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                    child: Container(height: 22, width: 2, color: borderColor),
                  ),
                  _tripRow(
                    Icons.location_on_outlined,
                    AppColors.accentRed,
                    context.tr('drop'),
                    widget.destination,
                    textColor,
                    subColor,
                  ),
                  Divider(height: 28, color: borderColor),
                  if (_passengerName.isNotEmpty) ...[
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.secondary.withAlpha(40),
                          child: Icon(
                            Icons.person,
                            color: AppColors.secondary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('passenger'),
                                style: TextStyle(fontSize: 10, color: subColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _passengerName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              if (_passengerPhone.isNotEmpty &&
                                  _passengerPhone != '—') ...[
                                const SizedBox(height: 2),
                                Text(
                                  _passengerPhone,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    Divider(height: 28, color: borderColor),
                  ],
                  // Ride info row: type + distance + duration
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('rideType'),
                              style: TextStyle(fontSize: 11, color: subColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.rideType,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_distance.isNotEmpty && _distance != '—') ...[
                        _infoChip(Icons.route_outlined, _distance, textColor),
                        const SizedBox(width: 12),
                      ],
                      if (_duration.isNotEmpty && _duration != '—')
                        _infoChip(
                          Icons.access_time_rounded,
                          _duration,
                          textColor,
                        ),
                    ],
                  ),
                  // Fare chip — only shown on the final accept/decline popup
                  // (isAssigned=true). On the initial interest screen the fare
                  // hasn't been negotiated yet so we don't show it.
                  if (widget.isAssigned &&
                      ((widget.fare != null && widget.fare!.isNotEmpty) ||
                          _currentRideData?['fare'] != null)) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.secondary.withAlpha(80),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.currency_rupee,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            () {
                              final fareRaw =
                                  widget.fare ??
                                  _currentRideData?['fare']?.toString() ??
                                  '';
                              // Strip currency symbol if present
                              return fareRaw
                                  .replaceAll('₹', '')
                                  .replaceAll('Rs', '')
                                  .trim();
                            }(),
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Fare',
                            style: TextStyle(
                              color: AppColors.secondary.withAlpha(180),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // ── Chat with passenger ─────────────────────────────────
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Pause timer while in chat so driver doesn't lose time
                        _timer?.cancel();
                        if (widget.rideId.isEmpty || _driverId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Chat unavailable — ride not ready yet.',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          // Resume countdown
                          _startCountdown();
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              rideId: widget.rideId,
                              senderId: _driverId,
                              senderModel: 'driver',
                              otherPartyName: _passengerName.isNotEmpty
                                  ? _passengerName
                                  : 'Passenger',
                            ),
                          ),
                        ).then((_) {
                          // Resume countdown after returning from chat
                          if (mounted && _countdown > 0) _startCountdown();
                        });
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                      ),
                      label: Text(
                        _passengerName.isNotEmpty
                            ? 'Chat with $_passengerName'
                            : 'Chat with Passenger',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentStrong,
                        side: BorderSide(
                          color: AppColors.accentStrong.withAlpha(160),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_acceptError != null) ...[
          Text(
            _acceptError!,
            style: AppTextStyles.body.copyWith(
              color: AppColors.accentRed,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: CustomButton(
                label: widget.isAssigned ? 'Cancel' : 'Ignore',
                isOutlined: true,
                color: AppColors.accentRed,
                onPressed: _accepting ? () {} : (widget.isAssigned ? _cancel : _decline),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: CustomButton(
                label: _accepting
                    ? 'Processing...'
                    : (widget.isAssigned ? 'Accept Ride' : "I'm Available"),
                color: AppColors.accentStrong,
                onPressed: _accepting ? () {} : _accept,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tripRow(
    IconData icon,
    Color iconColor,
    String label,
    String value,
    Color textColor,
    Color subColor,
  ) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: subColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _infoChip(IconData icon, String value, Color textColor) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppColors.accentStrong),
      const SizedBox(width: 5),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: textColor,
        ),
      ),
    ],
  );
}
