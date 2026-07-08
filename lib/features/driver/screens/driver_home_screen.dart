import 'dart:async';
import 'dart:ui' as ui;
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/services/ride_request_service.dart';
import '../../../core/services/ride_status.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shown_rides_storage.dart';
import '../../../core/services/firebase_notification_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/home_banner_carousel.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/widgets/chat_screen.dart';
import '../../auth/screens/welcome_screen.dart';
import '../data/driver_repository.dart';
import 'driver_trips_history_screen.dart';
import 'driver_profile_screen.dart';
import 'ride_request_screen.dart';
import 'driver_active_ride_screen.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../screens/driver/subscription_blocked_screen.dart';
import '../../../services/subscription_service.dart';
import '../../../services/category_service.dart';
import '../../../core/services/map_utils.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/device_utils.dart';
import '../../../core/models/ride.dart';
import '../../../main.dart' show consumePendingRideId, globalPendingRideAction;

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  bool _isOnline = false;
  bool _isShowingRequestScreen = false;
  int _bottomNavIndex = 0;
  DateTime? _wentOnlineAt;
  Timer? _pollTimer;
  Timer? _currentRideTimer;
  Timer? _dashboardSyncTimer;
  Timer? _locationEmitTimer;
  bool _isSyncingDashboard = false;
  int _completedTrips = 0;
  double _totalDistanceKm = 0.0;
  final _subscriptionService = SubscriptionService.instance;

  // FCM foreground listener — handles ride_assigned push from backend
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  // Completed ride history — grows as rides finish
  final List<Map<String, dynamic>> _tripHistory = [];

  // Map state variables
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  final Map<String, BitmapDescriptor> _emojiMarkerCache = {};
  BitmapDescriptor? _auto3DMarkerDescriptor;
  StreamSubscription<Position>? _positionSubscription;
  DateTime? _lastLocationUpdateTime;
  LatLng? _lastUploadedLatLng;

  Ride? _activeRide;

  Future<void> _updateLocationOnServer(double lat, double lng) async {
    if (!_isOnline) return;
    final now = DateTime.now();
    if (_lastLocationUpdateTime != null &&
        now.difference(_lastLocationUpdateTime!).inSeconds < 2) {
      return;
    }
    // Removed the distance filter so it updates every 2 seconds continuously
    _lastLocationUpdateTime = now;
    _lastUploadedLatLng = LatLng(lat, lng);
    final driverId = await SessionService.getDriverId();
    if (driverId != null && driverId.isNotEmpty) {
      // Use the new dedicated location update endpoint
      await ApiService.updateDriverLocationOnly(
        driverId: driverId,
        lat: lat,
        lng: lng,
      );
      // We ALSO update the status to keep it fresh, without overriding the new location endpoint.
      await ApiService.updateDriverStatus(
        driverId: driverId,
        status: 'online',
        available: true,
      );
    }
  }

  Future<BitmapDescriptor> _get3DAutoMarker() async {
    if (_auto3DMarkerDescriptor != null) return _auto3DMarkerDescriptor!;
    try {
      _auto3DMarkerDescriptor = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(80, 80)),
        'assets/auto_3d.png',
      );
      return _auto3DMarkerDescriptor!;
    } catch (e) {
      debugPrint('Error loading 3D auto marker asset: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<BitmapDescriptor> _get3DVehicleEmojiMarker(String emoji) async {
    final cacheKey = '3d_$emoji';
    if (_emojiMarkerCache.containsKey(cacheKey)) {
      return _emojiMarkerCache[cacheKey]!;
    }

    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      const double size = 120.0;
      const double center = size / 2;

      // Draw shadow
      final paintShadow = Paint()
        ..color = Colors.black.withAlpha((0.25 * 255).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(const Offset(center, center + 4), 42, paintShadow);

      // Draw outer glossy border/circle
      final paintCircle = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(size, size),
          [Colors.white, AppColors.secondary.withAlpha((0.8 * 255).round())],
        );
      canvas.drawCircle(const Offset(center, center), 42, paintCircle);

      // Draw inner glossy circle
      final paintInner = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(size, size),
          [AppColors.surface, AppColors.surfaceSoft],
        );
      canvas.drawCircle(const Offset(center, center), 35, paintInner);

      // Draw the emoji
      final TextPainter textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      textPainter.text = TextSpan(
        text: emoji,
        style: const TextStyle(fontSize: 48),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center - textPainter.width / 2, center - textPainter.height / 2),
      );

      final ui.Image image = await pictureRecorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        return BitmapDescriptor.defaultMarker;
      }

      final descriptor = BitmapDescriptor.fromBytes(
        byteData.buffer.asUint8List(),
      );
      _emojiMarkerCache[cacheKey] = descriptor;
      return descriptor;
    } catch (e) {
      debugPrint('Error creating 3D emoji marker: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  bool get _supportsMap {
    final key = AppConstants.googlePlacesApiKey;
    final validKey = key.isNotEmpty && !key.startsWith('YOUR_');
    return validKey &&
        (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  String get _driverEmoji {
    final type = _vehicleType.toLowerCase();
    if (type.contains('bike')) {
      return 'ðŸ›µ';
    } else if (type.contains('auto') || type.contains('rickshaw')) {
      return 'ðŸ›º';
    }
    return 'ðŸš—';
  }

  Future<BitmapDescriptor> _getEmojiMarker(String emoji) async {
    if (_emojiMarkerCache.containsKey(emoji)) {
      return _emojiMarkerCache[emoji]!;
    }

    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      const double size = 90.0;

      final TextPainter textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );

      textPainter.text = TextSpan(
        text: emoji,
        style: const TextStyle(fontSize: size),
      );

      textPainter.layout();
      textPainter.paint(canvas, const Offset(0, 0));

      final ui.Image image = await pictureRecorder.endRecording().toImage(
        textPainter.width.toInt(),
        textPainter.height.toInt(),
      );

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        return BitmapDescriptor.defaultMarker;
      }

      final descriptor = BitmapDescriptor.fromBytes(
        byteData.buffer.asUint8List(),
      );
      _emojiMarkerCache[emoji] = descriptor;
      return descriptor;
    } catch (e) {
      debugPrint('Error creating emoji marker: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _initLocationMonitoring() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentLatLng = LatLng(pos.latitude, pos.longitude);
        });
      }

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((Position p) {
            if (mounted) {
              setState(() {
                _currentLatLng = LatLng(p.latitude, p.longitude);
              });
              if (_isOnline) {
                _updateLocationOnServer(p.latitude, p.longitude);
              }
              if (_mapController != null && _currentLatLng != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: _currentLatLng!,
                      zoom: 16.0,
                      tilt: 0.0,
                    ),
                  ),
                );
              }
            }
          });
    } catch (e) {
      debugPrint('Error monitoring driver location: $e');
    }
  }

  void _onPendingRideActionChanged() {
    final pendingAction = consumePendingRideId();
    if (pendingAction != null && pendingAction.isNotEmpty) {
      debugPrint(
        '[REACTIVE] Handling pending action from notification tap: $pendingAction',
      );
      FirebaseNotificationService()
          .cancelAllNotifications(); // Stop notification sound immediately
      if (pendingAction.startsWith('new_ride:')) {
        _handleNewRequestPush(pendingAction.substring(9).trim());
      } else if (pendingAction.startsWith('ride:')) {
        _handleRideAssignedPush(pendingAction.substring(5).trim());
      } else {
        _handleRideAssignedPush(pendingAction);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscriptionService.addListener(_onSubscriptionChanged);
    _loadShownRideIds();
    _checkActiveRide();
    _startDashboardSyncTimer();
    _initLocationMonitoring();
    _setupFcmListener();
    globalPendingRideAction.addListener(_onPendingRideActionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSubscription();
      CategoryService.instance.fetchCategories(role: 'driver');
      // Consume any pending payload from a notification tap that launched the app
      _onPendingRideActionChanged();
      // Unconditionally cancel any ringing background notifications if app was opened normally via app icon
      FirebaseNotificationService().cancelAllNotifications();
      // Request notification and battery optimization permissions right after login
      _requestPermissionsOnInit();
    });
  }

  void _showPermissionDialog(
    String title,
    String content,
    VoidCallback onOpenSettings,
  ) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onOpenSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissionsOnInit() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      final hasAskedBatteryOpt = prefs.getBool('asked_battery_opt') ?? false;
      if (!hasAskedBatteryOpt) {
        await prefs.setBool('asked_battery_opt', true);
        if (await Permission.ignoreBatteryOptimizations.isDenied) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }

      final locStatus = await Permission.location.request();
      if (locStatus.isDenied || locStatus.isPermanentlyDenied) {
        _showPermissionDialog(
          'Location Required',
          'We need your location to assign rides and track distance. Please enable it.',
          () => openAppSettings(),
        );
      } else {
        if (await Permission.locationAlways.isDenied) {
          await Permission.locationAlways.request();
        }
      }
    } catch (e) {
      debugPrint('Error requesting permissions on init: $e');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final hasAskedAutoStart = prefs.getBool('asked_auto_start') ?? false;

        if (!hasAskedAutoStart) {
          await prefs.setBool('asked_auto_start', true);
          final available = await isAutoStartAvailable;
          if (available == true) {
            await getAutoStartPermission();
          }
        }
      } catch (e) {
        debugPrint('Auto-start permission error: $e');
      }

      // Fetch dashboard data sequentially after other permissions
      await _syncDashboardData();

      // Check overlay permission unconditionally during init
      try {
        bool status = await FlutterOverlayWindow.isPermissionGranted();
        if (!status) {
          debugPrint('🔴 [INIT] Requesting overlay permission...');
          await FlutterOverlayWindow.requestPermission();

          // Re-check after user returns
          bool finalStatus = await FlutterOverlayWindow.isPermissionGranted();
          if (!finalStatus) {
            _showPermissionDialog(
              'Bubble Head Permission',
              'To show the bubble head when the app is in the background, please enable "Display over other apps".',
              () => FlutterOverlayWindow.requestPermission(),
            );
          }
        }
      } catch (e) {
        debugPrint('Overlay permission error on init: $e');
      }
    }
  }

  void _onSubscriptionChanged() {
    if (mounted) setState(() {});
  }

  // â”€â”€ FCM foreground listener â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //
  // The backend sends a push with data.event = 'ride_assigned' when the user
  // chooses a specific driver from the available-drivers list.
  //
  // On receiving this event the driver app navigates directly to
  // DriverActiveRideScreen — bypassing the polling cycle entirely.
  void _setupFcmListener() {
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) async {
      final event = message.data['event']?.toString() ?? '';
      final type = message.data['type']?.toString() ?? '';
      final pushType = message.data['push_type']?.toString() ?? '';
      final rideId = message.data['rideId']?.toString() ?? '';
      debugPrint(
        '[FCM] DriverHome: event=$event type=$type pushType=$pushType rideId=$rideId',
      );

      final isRideCancelled =
          event == 'bid_rejected_by_user' ||
          event == 'ride_cancelled' ||
          type == 'ride_cancelled' ||
          type == 'bid_rejected_by_user';

      // Handle strict ride assignment events (user accepted driver's bid)
      final isRideAssigned =
          !isRideCancelled &&
          (event == 'ride_assigned' ||
              type == 'ride_assigned' ||
              pushType == 'ride_assigned');

      // Handle new incoming requests
      final isNewRequest =
          !isRideCancelled &&
          !isRideAssigned &&
          (event == 'new_request' ||
              type == 'ride_request' ||
              type == 'ride' ||
              pushType == 'ride' ||
              pushType == 'ride_request');

      if (isRideCancelled && rideId.isNotEmpty) {
        debugPrint('[FCM] User cancelled the ride. Dismissing from UI.');
        _ignoredRideIds.add(rideId);
        RideRequestService.removeRequestByRideId(rideId);
        if (mounted) {
          bool wasWaiting = false;
          setState(() {
            if (_waitingRides.containsKey(rideId)) {
              wasWaiting = true;
              _waitingRides.remove(rideId);
              _waitingCheckTickCount = 0;
            }
          });
          if (_isShowingRequestScreen) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context, 'cancelled');
              wasWaiting = true;
            }
          }
          if (wasWaiting) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Ride Cancelled'),
                content: const Text(
                  'The user has cancelled this ride request.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      } else if (isRideAssigned && rideId.isNotEmpty) {
        debugPrint('[FCM] ride assigned push → showing accept/decline');
        await _handleRideAssignedPush(rideId);
      } else if (isNewRequest) {
        debugPrint('[FCM] new ride request push → handling directly');
        unawaited(_handleNewRequestPush(rideId));
      }
    });
  }

  /// Called when the backend pushes a ride_assigned/ride_request event via FCM.
  /// Routes through [RideRequestScreen] so the driver can accept or decline
  /// before being taken to [DriverActiveRideScreen].
  Future<void> _handleNewRequestPush(String rideId) async {
    if (!mounted) return;
    if (_isShowingRequestScreen) {
      debugPrint(
        '[FCM] Request screen already active, skipping new_request push for rideId: $rideId',
      );
      return;
    }
    if (_shownRideIds.contains(rideId) || _ignoredRideIds.contains(rideId)) {
      return;
    }

    // Acquire lock synchronously to prevent concurrent popups
    setState(() => _isShowingRequestScreen = true);

    try {
      final driverId = await SessionService.getDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final res = await ApiService.getRide(rideId);
      if (!mounted) return;
      if (res.statusCode == 404 || !res.success || res.data.isEmpty) {
        await _markRideIgnored(rideId);
        return;
      }

      final rideData = ApiService.normalizeDriverRidePayload(
        res.data,
        fallbackDriverId: driverId,
      );

      // Check if ride is already cancelled before showing popup
      final status = rideData['status']?.toString().toLowerCase() ?? '';
      if (status == 'cancelled' || status == 'completed') {
        debugPrint('[FCM] Ride $rideId is already $status. Aborting push.');
        await _markRideIgnored(rideId);
        return;
      }

      RideRequestService.queueRideRequest(rideData);

      final pickup =
          rideData['pickupLocation']?.toString() ??
          rideData['pickup']?.toString() ??
          'Pickup';
      final destination =
          rideData['destination']?.toString() ??
          rideData['dropoffLocation']?.toString() ??
          'Destination';
      final rType =
          rideData['rideType']?.toString() ??
          rideData['vehicleType']?.toString() ??
          _vehicleType;
      final dist = ApiService.formatDistanceDisplay(
        rideData['distance'] ?? rideData['distanceKm'],
      );
      final dur = ApiService.formatDurationDisplay(
        rideData['duration'] ?? rideData['durationMin'],
      );
      final fareNum = ApiService.resolveRideFare(rideData);
      final fare = fareNum?.toString();

      _pollTimer?.cancel();

      await _markRideAsShown(rideId, driverId);

      String? result;
      result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => RideRequestScreen(
            rideId: rideId,
            pickup: pickup,
            destination: destination,
            distance: dist != '—' ? dist : '—',
            rideType: rType,
            duration: dur != '—' ? dur : '—',
            fare: fare,
            isAssigned: false,
          ),
        ),
      );

      if (!mounted) return;

      if (result == 'interested') {
        setState(() {
          _waitingRides[rideId] = rideData;
          _interestReflected = true;
          _waitingCheckTickCount = 0;
        });
        _startPolling();
      } else {
        await _markRideIgnored(rideId);
        RideRequestService.removeRequestByRideId(rideId);
        
        final driverId = await SessionService.getDriverId();
        if (driverId != null && driverId.isNotEmpty) {
          ApiService.ignoreBroadcastRide(rideId: rideId, driverId: driverId)
              .then((res) {
            if (res.success) {
              debugPrint('✅ [IGNORE] Successfully ignored broadcast $rideId from push');
            } else {
              debugPrint('⚠️ [IGNORE] Failed to ignore broadcast from push: ${res.errorMessage}');
            }
          });
        }
        
        _startPolling();
      }
    } finally {
      if (mounted) setState(() => _isShowingRequestScreen = false);
    }
  }

  Future<void> _handleRideAssignedPush(String rideId) async {
    if (!mounted) return;
    if (_isShowingRequestScreen) {
      debugPrint(
        '[FCM] Request screen already active, skipping push for rideId: $rideId',
      );
      return;
    }

    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) return;

    // Fetch full ride details so we have pickup/destination/fare/etc.
    final res = await ApiService.getRide(rideId);
    if (!mounted) return;

    if (res.statusCode == 404) {
      debugPrint(
        '[FCM] Ride details fetch returned 404 for rideId: $rideId. Aborting and ignoring.',
      );
      await _markRideIgnored(rideId);
      return;
    }

    if (!res.success || res.data.isEmpty) {
      debugPrint(
        '[FCM] Ride details fetch failed (status=${res.statusCode}) for rideId: $rideId. Skipping push.',
      );
      return;
    }

    final rideData = ApiService.normalizeDriverRidePayload(
      res.data,
      fallbackDriverId: driverId,
    );

    // Check if ride is already cancelled before assigning
    final status = rideData['status']?.toString().toLowerCase() ?? '';
    if (status == 'cancelled' || status == 'completed') {
      debugPrint('[FCM] Assigned ride $rideId is already $status. Aborting.');
      await _markRideIgnored(rideId);
      return;
    }

    // Let the centralized polling logic handle the assignment. It already contains
    // the complex logic to show the Accept Ride screen, call the acceptRide API,
    // and navigate to the Active Ride screen.
    setState(() {
      _waitingRides[rideId] = rideData;
      // Pretend we already reflected interest so it doesn't clear the state early
      _interestReflected = true;
    });

    _performPollingTick();
  }

  Future<void> _initSubscription() async {
    await _subscriptionService.fetchSubscription();
    _subscriptionService.updatePerformanceDistance(_totalDistanceKm);
    if (!mounted) return;
    if (_subscriptionService.isBlocked) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionBlockedScreen()),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _markDriverOffline();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed');
      if (defaultTargetPlatform == TargetPlatform.android) {
        FlutterOverlayWindow.closeOverlay();
      }
      FirebaseNotificationService().cancelAllNotifications();
      _startDashboardSyncTimer();
      // Consume any payload stored from a notification tap while backgrounded
      final pendingAction = consumePendingRideId();
      if (pendingAction != null && pendingAction.isNotEmpty) {
        debugPrint('[RESUME] Handling pending action: $pendingAction');
        if (pendingAction.startsWith('new_ride:')) {
          _handleNewRequestPush(pendingAction.substring(9).trim());
        } else if (pendingAction.startsWith('ride:')) {
          _handleRideAssignedPush(pendingAction.substring(5).trim());
        } else {
          _handleRideAssignedPush(pendingAction);
        }
      } else if (_isOnline) {
        // Restart the timer AND fire an immediate tick — no 1s wait
        _startPolling();
        _performPollingTick();
      }
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _dashboardSyncTimer?.cancel();
      debugPrint('🔴 [LIFECYCLE] AppLifecycleState.paused triggered');
      if (_isOnline && defaultTargetPlatform == TargetPlatform.android) {
        debugPrint(
          '🔴 [OVERLAY] Attempting to check permission and show overlay...',
        );
        FlutterOverlayWindow.isPermissionGranted()
            .then((granted) async {
              debugPrint('🔴 [OVERLAY] Permission granted status: $granted');
              if (granted) {
                try {
                  debugPrint('🔴 [OVERLAY] Calling showOverlay()...');
                  await FlutterOverlayWindow.showOverlay(
                    enableDrag: true,
                    overlayTitle: "Chal Chal Gaadi",
                    overlayContent: "Online",
                    flag: OverlayFlag.defaultFlag,
                    visibility: NotificationVisibility.visibilityPublic,
                    positionGravity: PositionGravity.auto,
                    height: 120,
                    width: 120,
                  );
                  debugPrint('🔴 [OVERLAY] showOverlay executed successfully');
                } catch (e, stackTrace) {
                  debugPrint(
                    '🔴 [OVERLAY] ERROR in showOverlay: $e\n$stackTrace',
                  );
                }
              } else {
                debugPrint(
                  '🔴 [OVERLAY] Permission is NOT granted. Cannot show overlay.',
                );
              }
            })
            .catchError((e) {
              debugPrint('🔴 [OVERLAY] ERROR checking permission: $e');
            });
      }
    }
  }

  void _startDashboardSyncTimer() {
    _dashboardSyncTimer?.cancel();
    _dashboardSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _syncDashboardData();
        _checkActiveRide();
      }
    });

    _locationEmitTimer?.cancel();
    _locationEmitTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _isOnline && _currentLatLng != null) {
        _updateLocationOnServer(
          _currentLatLng!.latitude,
          _currentLatLng!.longitude,
        );
      }
    });
  }

  Future<void> _checkActiveRide() async {
    try {
      final driverId = await SessionService.getDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final res = await ApiService.getDriverCurrentActiveRide(driverId);
      if (!mounted) return;

      if (res.success) {
        final ride = Ride.fromJson(res.data);
        final status = ride.status;
        if (RideStatus.isAccepted(status) || RideStatus.isOngoing(status)) {
          setState(() => _activeRide = ride);
        } else {
          setState(() => _activeRide = null);
        }
      } else {
        if (_activeRide != null && mounted) {
          setState(() => _activeRide = null);
        }
      }
    } catch (e) {
      debugPrint('Error checking active ride: $e');
    }
  }

  void _startCurrentRidePolling() async {
    // DISABLED: This was automatically accepting rides without showing RideRequestScreen
    // Use _performPollingTick() instead which shows RideRequestScreen for accept/decline
    return;

    // Legacy code - DO NOT USE
    // final driverId = await SessionService.getDriverId();
    // if (driverId == null || driverId.isEmpty) return;
    // ...
  }

  Map<String, dynamic>? _extractRidePayload(Map<String, dynamic> data) {
    final rideValue = data['ride'];
    if (rideValue is Map<String, dynamic>) return rideValue;
    if (data.containsKey('ride')) return null;
    if (data.containsKey('rideId') ||
        data.containsKey('status') ||
        data.containsKey('rideStatus')) {
      return data;
    }
    return null;
  }

  Future<void> _syncDashboardData() async {
    if (_isSyncingDashboard) return;
    _isSyncingDashboard = true;
    try {
      final session = await SessionService.getSession();
      final phone = session['phone'] ?? '';
      final vehicleNo = session['vehicleNumber'] ?? '';
      String? driverId = session['id'];
      if (driverId == null || driverId.isEmpty || driverId == 'mock') {
        driverId = DriverRepository.currentDriver?['id'];
      }

      // If driverId is not available, try to login to retrieve it
      if ((driverId == null || driverId.isEmpty || driverId == 'mock') &&
          phone.isNotEmpty &&
          vehicleNo.isNotEmpty) {
        final fcmToken = await FirebaseNotificationService().getToken();
        final deviceInfo = await DeviceUtils.getDeviceInfo();
        final loginRes = await ApiService.driverLogin(
          phone: phone,
          vehicleNumber: vehicleNo,
          fcmToken: fcmToken,
          deviceInfo: deviceInfo,
        );
        if (loginRes.success) {
          final raw = loginRes.data;
          final Map<String, dynamic> driverData =
              (raw['driver'] is Map<String, dynamic>)
              ? raw['driver'] as Map<String, dynamic>
              : raw;
          driverId =
              driverData['id']?.toString() ??
              driverData['_id']?.toString() ??
              driverData['driverId']?.toString();
        }
      }

      if (driverId != null && driverId.isNotEmpty && driverId != 'mock') {
        final dashboardFuture = ApiService.getDriverDashboard(driverId);
        final ridesFuture = ApiService.getDriverRides(driverId);
        final profileFuture = ApiService.getDriverProfile(driverId);

        final results = await Future.wait([
          dashboardFuture,
          ridesFuture,
          profileFuture,
        ]);
        final res = results[0];
        final ridesRes = results[1];
        final profileRes = results[2];

        if (res.success || profileRes.success || ridesRes.success) {
          final raw = res.success ? res.data : <String, dynamic>{};
          final Map<String, dynamic> dashboardDriverData =
              (raw['driver'] is Map<String, dynamic>)
              ? raw['driver'] as Map<String, dynamic>
              : {};

          final Map<String, dynamic> profileData = profileRes.success
              ? profileRes.data
              : {};

          final id =
              profileData['id']?.toString() ??
              profileData['_id']?.toString() ??
              dashboardDriverData['id']?.toString() ??
              dashboardDriverData['_id']?.toString() ??
              dashboardDriverData['driverId']?.toString() ??
              driverId;
          final name =
              profileData['name']?.toString() ??
              dashboardDriverData['name']?.toString() ??
              _driverName;
          final vehicleNumber =
              profileData['vehicleNumber']?.toString().isNotEmpty == true
              ? profileData['vehicleNumber'].toString()
              : (dashboardDriverData['vehicleNumber']?.toString().isNotEmpty ==
                        true
                    ? dashboardDriverData['vehicleNumber'].toString()
                    : vehicleNo);
          final vehicleType =
              profileData['vehicleType']?.toString() ??
              dashboardDriverData['vehicleType']?.toString() ??
              _vehicleType;
          final rawStatus =
              profileData['verificationStatus']?.toString() ??
              dashboardDriverData['verificationStatus']?.toString() ??
              'pending';
          final verificationStatus = (rawStatus.toLowerCase() == 'approved')
              ? 'verified'
              : rawStatus;
          final rejectionReason =
              profileData['rejectionReason']?.toString() ??
              dashboardDriverData['rejectionReason']?.toString() ??
              '';

          // Parse experienceYears (can be int, double, or String)
          final rawExp =
              profileData['experienceYears'] ??
              dashboardDriverData['experienceYears'];
          String experience = '—';
          if (rawExp != null &&
              rawExp.toString() != '0' &&
              rawExp.toString() != 'null') {
            final expStr = rawExp.toString().trim();
            if (expStr.isNotEmpty) {
              if (RegExp(r'^\d+$').hasMatch(expStr)) {
                experience = '$expStr years';
              } else {
                experience = expStr;
              }
            }
          }

          if (experience == '—') {
            final details =
                profileData['driverVerificationDetails']?.toString() ??
                dashboardDriverData['driverVerificationDetails']?.toString() ??
                profileData['experience']?.toString() ??
                dashboardDriverData['experience']?.toString() ??
                '';
            if (details.isNotEmpty) {
              experience = details;
            }
          }

          final profileRating = profileData['rating']?.toString();
          final dashboardRating = dashboardDriverData['rating']?.toString();
          String rating = '4.9';
          if (profileRating != null &&
              profileRating != '0' &&
              profileRating != '0.0' &&
              profileRating.isNotEmpty) {
            rating = profileRating;
          } else if (dashboardRating != null &&
              dashboardRating != '0' &&
              dashboardRating != '0.0' &&
              dashboardRating.isNotEmpty) {
            rating = dashboardRating;
          }

          final vehicleModel =
              profileData['vehicle']?.toString() ??
              profileData['vehicleModel']?.toString() ??
              dashboardDriverData['vehicle']?.toString() ??
              dashboardDriverData['vehicleModel']?.toString() ??
              '';

          // Parse stats
          final stats = raw['stats'] as Map<String, dynamic>?;
          int completedTrips = 0;
          double totalDistanceKm = 0.0;
          if (stats != null) {
            completedTrips =
                int.tryParse(stats['totalTrips']?.toString() ?? '0') ?? 0;
            totalDistanceKm =
                double.tryParse(
                  stats['totalDistanceKm']?.toString() ?? '0.0',
                ) ??
                0.0;
          }

          // Parse and merge trip history
          final List<Map<String, dynamic>> parsedHistory = [];

          void parseAndAddRide(dynamic item) {
            if (item is Map<String, dynamic>) {
              // Normalize payload using ApiService helper
              final normalized = ApiService.normalizeDriverRidePayload(
                item,
                fallbackDriverId: driverId,
              );

              final pickup = normalized['pickup']?.toString() ?? 'Pickup';
              final dest =
                  normalized['destination']?.toString() ?? 'Destination';
              final rType = normalized['rideType']?.toString() ?? vehicleType;

              var distStr = '—';
              if (normalized['distance'] != null) {
                distStr = normalized['distance'].toString();
                if (!distStr.toLowerCase().contains('km') &&
                    double.tryParse(distStr) != null) {
                  distStr = '$distStr km';
                }
              }

              var durStr = '—';
              if (normalized['duration'] != null) {
                durStr = normalized['duration'].toString();
                if (!durStr.toLowerCase().contains('min') &&
                    int.tryParse(durStr) != null) {
                  durStr = '$durStr mins';
                }
              }

              var dateStr = '—';
              var timeStr = '—';
              if (normalized['date'] != null) {
                dateStr = normalized['date'].toString();
              }
              if (normalized['time'] != null) {
                timeStr = normalized['time'].toString();
              }
              if ((dateStr == '—' || timeStr == '—') &&
                  normalized['createdAt'] != null) {
                try {
                  final parsedDate = DateTime.parse(
                    normalized['createdAt'].toString(),
                  );
                  if (dateStr == '—') {
                    dateStr = _formatDate(parsedDate);
                  }
                  if (timeStr == '—') {
                    timeStr = _formatTime(parsedDate);
                  }
                } catch (_) {
                  if (dateStr == '—') {
                    dateStr = normalized['createdAt'].toString();
                  }
                }
              }

              final userMap = (normalized['user'] is Map)
                  ? normalized['user']
                  : ((normalized['rider'] is Map)
                        ? normalized['rider']
                        : ((normalized['passenger'] is Map)
                              ? normalized['passenger']
                              : normalized['userId']));

              String riderName = '';
              String riderPhone = '—';
              if (userMap is Map<String, dynamic>) {
                riderName =
                    userMap['name']?.toString() ??
                    userMap['userName']?.toString() ??
                    userMap['passengerName']?.toString() ??
                    '';
                riderPhone =
                    userMap['phone']?.toString() ??
                    userMap['passengerPhone']?.toString() ??
                    userMap['userPhone']?.toString() ??
                    '—';
              }
              if (riderName.trim().isEmpty) {
                final fallbackName =
                    normalized['riderName']?.toString() ??
                    normalized['passengerName']?.toString() ??
                    normalized['userName']?.toString() ??
                    normalized['customerName']?.toString() ??
                    normalized['name']?.toString() ??
                    '';
                riderName = fallbackName.trim().isNotEmpty
                    ? fallbackName
                    : 'Passenger';
              }
              if (riderPhone == '—' || riderPhone.trim().isEmpty) {
                riderPhone =
                    normalized['riderPhone']?.toString() ??
                    normalized['passengerPhone']?.toString() ??
                    normalized['userPhone']?.toString() ??
                    normalized['phone']?.toString() ??
                    '—';
              }

              final idStr =
                  normalized['rideId']?.toString() ??
                  normalized['_id']?.toString() ??
                  normalized['id']?.toString() ??
                  '';

              // Avoid adding duplicate rides in the list
              if (parsedHistory.any(
                (element) => element['id'] == idStr && idStr.isNotEmpty,
              )) {
                return;
              }

              final status =
                  normalized['status']?.toString().toLowerCase() ?? 'completed';
              final startTime = normalized['startTime']?.toString() ?? timeStr;
              final endTime = normalized['endTime']?.toString() ?? '—';

              var fare =
                  normalized['fare']?.toString() ??
                  normalized['finalFare']?.toString() ??
                  normalized['price']?.toString() ??
                  normalized['estimatedFare']?.toString() ??
                  '—';
              if (fare != '—' && fare.trim().isNotEmpty) {
                fare = fare.replaceAll(RegExp(r'[^0-9.]'), '');
              } else {
                fare = '—';
              }

              final rating = normalized['rating']?.toString() ?? '—';
              final passengerId = userMap is Map
                  ? (userMap['_id'] ?? userMap['id'])?.toString() ?? ''
                  : normalized['userId']?.toString() ?? '';
              final drId =
                  normalized['driverId']?.toString() ??
                  normalized['assignedDriverId']?.toString() ??
                  '';

              if (status == 'completed' || status == 'ended') {
                parsedHistory.add({
                  'id': idStr,
                  'rideId': idStr,
                  'pickup': pickup,
                  'destination': dest,
                  'rideType': rType,
                  'distance': distStr,
                  'duration': durStr,
                  'date': dateStr,
                  'time': timeStr,
                  'riderName': riderName,
                  'passengerName': riderName,
                  'riderPhone': riderPhone,
                  'passengerPhone': riderPhone,
                  'startTime': startTime,
                  'endTime': endTime,
                  'fare': fare,
                  'rating': rating,
                  'createdAt': normalized['createdAt']?.toString() ?? '',
                  'userId': passengerId,
                  'driverId': drId,
                });
              }
            }
          }

          // 1. Parse rides from getDriverRides API
          final ridesList = ridesRes.success
              ? (ridesRes.data['rides'] as List<dynamic>? ?? [])
              : [];
          for (var item in ridesList) {
            parseAndAddRide(item);
          }

          // 2. Parse / merge rides from dashboard's tripHistory
          final historyList = raw['tripHistory'] as List<dynamic>? ?? [];
          for (var item in historyList) {
            parseAndAddRide(item);
          }

          // Calculate fallback stats if dashboard stats are not available
          if (stats == null) {
            completedTrips = parsedHistory.length;
            totalDistanceKm = 0.0;
            for (final ride in parsedHistory) {
              final distStr = ride['distance']?.toString() ?? '';
              final cleanDist = distStr.replaceAll(RegExp(r'[^0-9.]'), '');
              final val = double.tryParse(cleanDist);
              if (val != null) {
                totalDistanceKm += val;
              }
            }
          }

          // Read online status from backend
          bool? isOnlineFromBackend;
          final pIsOnline = profileData['isOnline'];
          final pAvailable = profileData['available'];
          final pStatus = profileData['status']?.toString().toLowerCase();
          final dIsOnline = dashboardDriverData['isOnline'];
          final dAvailable = dashboardDriverData['available'];
          final dStatus = dashboardDriverData['status']
              ?.toString()
              .toLowerCase();

          if (pIsOnline is bool) {
            isOnlineFromBackend = pIsOnline;
          } else if (pAvailable is bool) {
            isOnlineFromBackend = pAvailable;
          } else if (pStatus != null && pStatus.isNotEmpty) {
            isOnlineFromBackend = pStatus == 'online';
          } else if (dIsOnline is bool) {
            isOnlineFromBackend = dIsOnline;
          } else if (dAvailable is bool) {
            isOnlineFromBackend = dAvailable;
          } else if (dStatus != null && dStatus.isNotEmpty) {
            isOnlineFromBackend = dStatus == 'online';
          }

          await SessionService.saveDriver(
            id: id,
            name: name,
            phone: phone,
            vehicleNumber: vehicleNumber,
            vehicleType: vehicleType,
            verificationStatus: verificationStatus,
            rejectionReason: rejectionReason,
            experience: experience,
            rating: rating,
            vehicleModel: vehicleModel,
          );

          bool shouldStartPolling = false;

          if (mounted) {
            setState(() {
              DriverRepository.currentDriver = {
                ...?DriverRepository.currentDriver,
                'id': id,
                'name': name,
                'phone': phone,
                'vehicleNumber': vehicleNumber,
                'vehicleType': vehicleType,
                'verificationStatus': verificationStatus,
                'rejectionReason': rejectionReason,
                'experience': experience,
                'rating': rating,
                'vehicle': vehicleModel,
              };
              _completedTrips = completedTrips;
              _totalDistanceKm = totalDistanceKm;
              _subscriptionService.updatePerformanceDistance(_totalDistanceKm);
              _tripHistory.clear();
              _tripHistory.addAll(parsedHistory);

              if (verificationStatus == 'verified') {
                if (isOnlineFromBackend != null) {
                  final wasOnline = _isOnline;
                  _isOnline = isOnlineFromBackend;
                  if (_isOnline && !wasOnline) {
                    _wentOnlineAt = DateTime.now();
                    shouldStartPolling = true;
                  } else if (!_isOnline && wasOnline) {
                    _wentOnlineAt = null;
                    _pollTimer?.cancel();
                  }
                }
              } else {
                _isOnline = false;
                _pollTimer?.cancel();
              }
            });

            if (shouldStartPolling) {
              _loadShownRideIds();
              _startPolling();
              _performPollingTick();

              // Ensure background service starts if they are online on app launch
              FlutterBackgroundService().startService().then((success) {
                debugPrint(
                  '🚀 [Background Service] Auto-started on launch: $success',
                );
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing dashboard data: $e');
    } finally {
      _isSyncingDashboard = false;
    }
  }

  // â”€â”€ Current driver from session â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Map<String, dynamic> get _driver =>
      DriverRepository.currentDriver ??
      {'name': 'Driver', 'vehicleType': 'Auto', 'vehicle': '', 'rating': '4.9'};

  String get _driverName => _driver['name'] as String? ?? 'Driver';
  String get _vehicleType => _driver['vehicleType'] as String? ?? 'Auto';
  String get _vehicleModel => _driver['vehicle'] as String? ?? '';
  String get _vehicleNumber => _driver['vehicleNumber'] as String? ?? '';
  String get _rating => _driver['rating'] as String? ?? '4.9';
  String get _experience {
    final raw =
        (_driver['experience'] ?? _driver['driverVerificationDetails'])
            as String? ??
        '—';
    final match = RegExp(
      r'(\d+)\s*(years|year|yrs|yr)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match != null) {
      final number = match.group(1);
      return '$number years';
    }
    final lower = raw.toLowerCase().trim();
    if (lower.startsWith('experience:')) {
      return raw.substring(raw.indexOf(':') + 1).trim();
    }
    return raw;
  }

  String get _verificationStatus =>
      _driver['verificationStatus'] as String? ?? 'pending';
  String get _rejectionReason => _driver['rejectionReason'] as String? ?? '';

  // â”€â”€ Queued requests matching this driver's vehicleType â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<Map<String, dynamic>> get _matchingRequests {
    final since = _wentOnlineAt;
    return RideRequestService.requestsForVehicleType(_vehicleType).where((
      request,
    ) {
      if (since == null) return true;
      final createdAt = _parseRequestCreatedAt(request);
      return createdAt == null ||
          createdAt.isAtSameMomentAs(since) ||
          createdAt.isAfter(since);
    }).toList();
  }

  DateTime? _parseRequestCreatedAt(Map<String, dynamic> request) {
    final raw = request['requestedAt'] ?? request['createdAt'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  bool _isRequestNewerThanOnline(Map<String, dynamic> request) {
    final since = _wentOnlineAt;
    if (since == null) return true;
    final createdAt = _parseRequestCreatedAt(request);
    return createdAt == null ||
        createdAt.isAtSameMomentAs(since) ||
        createdAt.isAfter(since);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('logout')),
        content: Text(context.tr('logoutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accentRed),
            child: Text(context.tr('logout')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Best-effort backend offline call so driver is never trapped in app when network/server is down
    try {
      await _markDriverOffline();
    } catch (e) {
      debugPrint('Best-effort offline update failed: $e');
    }

    // Clear local data and in-memory state
    RideRequestService.clearQueue();
    DriverRepository.logout();
    await SessionService.clear();

    // Ensure the background foreground-service stops running after logout
    FlutterBackgroundService().invoke('stopService');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  /// Mark current driver as offline on the server and clear local queued requests.
  Future<bool> _markDriverOffline() async {
    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) {
      debugPrint('No driver session available while trying to logout.');
      return false;
    }

    // Cancel local polling immediately to prevent processing requests during logout.
    _pollTimer?.cancel();
    if (mounted) {
      setState(() => _isOnline = false);
    }

    try {
      final res = await ApiService.updateDriverStatus(
        driverId: driverId,
        status: 'offline',
        available: false,
      );
      if (!res.success) {
        debugPrint(
          'updateDriverStatus failed during logout: ${res.errorMessage}',
        );
        return false;
      }
      debugPrint('Driver marked offline on backend: $driverId');
      return true;
    } catch (e) {
      debugPrint('Exception while updating driver status: $e');
      return false;
    } finally {
      // Remove any pending local queue entries for this driver so they won't be delivered locally.
      try {
        RideRequestService.removeRequestsForDriver(driverId);
      } catch (e) {
        debugPrint(
          'Error clearing local queued requests for driver $driverId: $e',
        );
      }
    }
  }

  Future<Position?> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  void _toggleOnline(bool val) async {
    if (val && _verificationStatus != 'verified') {
      _showVerificationWarning();
      return;
    }

    if (val && _subscriptionService.isBlocked) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionBlockedScreen()),
      );
      return;
    }

    if (val) {
      final locStatus = await Permission.location.status;
      if (!locStatus.isGranted) {
        final req = await Permission.location.request();
        if (!req.isGranted) {
          _showPermissionDialog(
            'Location Required',
            'You must allow location access to go online and receive rides.',
            () => openAppSettings(),
          );
          // Keep the switch in the OFF state since they denied permission
          setState(() {
            _isOnline = false;
          });
          return;
        }
      }
    }

    setState(() {
      _isOnline = val;
      _wentOnlineAt = val ? DateTime.now() : null;
    });
    _updateStatusOnServer(val);

    if (val) {
      final success = await FlutterBackgroundService().startService();
      debugPrint('🚀 [Background Service] startService returned: $success');

      // SHOW OVERLAY PERMISSION PROMPT ONLY
      if (defaultTargetPlatform == TargetPlatform.android) {
        debugPrint('🔴 [TOGGLE_ONLINE] Checking overlay permission...');
        try {
          bool status = await FlutterOverlayWindow.isPermissionGranted();
          debugPrint(
            '🔴 [TOGGLE_ONLINE] Current overlay permission status: $status',
          );
          if (!status) {
            debugPrint('🔴 [TOGGLE_ONLINE] Requesting overlay permission...');
            final reqStatus = await FlutterOverlayWindow.requestPermission();
            debugPrint(
              '🔴 [TOGGLE_ONLINE] Requested overlay permission returned: $reqStatus',
            );
          }
        } catch (e) {
          debugPrint(
            '🔴 [TOGGLE_ONLINE] ERROR during overlay permission check: $e',
          );
        }
      }

      _loadShownRideIds();
      // Connect socket and join driver room for instant ride-request delivery
      SessionService.getDriverId().then((driverId) {
        if (driverId != null && driverId.isNotEmpty) {
          SocketService().connect();
          SocketService().joinDriverRoom(driverId);
          // Real-time ride request via socket (sub-100 ms delivery)
          SocketService().onNewRide((data) {
            debugPrint('âš¡ [SOCKET] New ride via socket: $data');
            if (!mounted || !_isOnline) return;
            // Queue it; guard prevents flooding if multiple socket events arrive fast
            RideRequestService.queueRideRequest({
              ...data,
              'driverId': driverId,
            });
            // Only trigger polling if not already running
            if (!_isPolling) _performPollingTick();
          });
        }
      });
      _startPolling();
      _performPollingTick();
    } else {
      FlutterBackgroundService().invoke('stopService');

      // CLOSE OVERLAY
      if (defaultTargetPlatform == TargetPlatform.android) {
        FlutterOverlayWindow.closeOverlay();
      }

      _pollTimer?.cancel();
      // Leave socket driver room and remove ride listeners
      SessionService.getDriverId().then((driverId) {
        if (driverId != null && driverId.isNotEmpty) {
          SocketService().leaveDriverRoom(driverId);
        }
        SocketService().offNewRide();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();

    debugPrint('Starting polling every 4 seconds');
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _isOnline) {
        _performPollingTick();
      }
    });
  }

  /// Refresh dashboard — fetch latest data from API
  Future<void> _refreshDashboard() async {
    debugPrint('[REFRESH] Refreshing driver dashboard...');

    try {
      // Show refresh animation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing...'),
          duration: Duration(seconds: 1),
          backgroundColor: AppColors.secondary,
        ),
      );

      // Refresh all dashboard data
      await _syncDashboardData();

      // If online, restart polling to get fresh ride requests
      if (_isOnline) {
        _pollTimer?.cancel();
        _startPolling();
        debugPrint(
          'SUCCESS [REFRESH] Dashboard refreshed and polling restarted',
        );
      } else {
        debugPrint(
          'SUCCESS [REFRESH] Dashboard refreshed (polling not active)',
        );
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SUCCESS Dashboard refreshed'),
            duration: Duration(seconds: 1),
            backgroundColor: AppColors.secondary,
          ),
        );
      }
    } catch (e) {
      debugPrint('ERROR [REFRESH] Error refreshing dashboard: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing: ${e.toString()}'),
            backgroundColor: AppColors.accentRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Track rides we've already shown to prevent duplicates (memory + storage)
  final Set<String> _shownRideIds = {};
  // Track rides driver explicitly ignored — never show again across sessions
  final Set<String> _ignoredRideIds = {};

  // Throttle counter: getRide() is called only every 3rd polling tick while waiting
  int _waitingCheckTickCount = 0;
  // Guard against concurrent polling ticks
  bool _isPolling = false;

  Future<void> _loadShownRideIds() async {
    final shown = await ShownRidesStorage.getShownRideIds();
    final ignored = await ShownRidesStorage.getIgnoredRideIds();
    if (!mounted) return;
    setState(() {
      _shownRideIds.addAll(shown);
      _ignoredRideIds.addAll(ignored);
    });
  }

  Future<void> _markRideAsShown(String rideId, String driverId) async {
    // Add to both sets immediately so no poll tick can re-show this ride
    _shownRideIds.add(rideId);
    // Pre-emptively add to ignored too — removed if driver says "I'm Available"
    _ignoredRideIds.add(rideId);
    unawaited(ShownRidesStorage.addShownRideId(rideId));
    unawaited(ShownRidesStorage.addIgnoredRideId(rideId));
    unawaited(
      ApiService.markDriverNotified(rideId: rideId, driverId: driverId),
    );
    // Remove from local queue so Step 2 doesn't re-offer it
    RideRequestService.removeRequestByRideId(rideId);
  }

  /// Called when driver explicitly ignores/declines — confirms the ignore.
  /// (ride was already pre-added to _ignoredRideIds in _markRideAsShown)
  Future<void> _markRideIgnored(String rideId) async {
    _shownRideIds.add(rideId);
    _ignoredRideIds.add(rideId);
    unawaited(ShownRidesStorage.addShownRideId(rideId));
    unawaited(ShownRidesStorage.addIgnoredRideId(rideId));
    RideRequestService.removeRequestByRideId(rideId);
  }

  /// Called when driver says "I'm Available" — removes from ignored set
  /// so the ride can proceed to the waiting/assignment phase.
  void _unmarkRideIgnored(String rideId) {
    _ignoredRideIds.remove(rideId);
    unawaited(ShownRidesStorage.removeIgnoredRideId(rideId));
  }

  String _rideIdFromData(Map<String, dynamic> rideData) =>
      rideData['rideId']?.toString() ??
      rideData['_id']?.toString() ??
      rideData['id']?.toString() ??
      '';

  String _assignedDriverIdFromData(Map<String, dynamic> rideData) =>
      rideData['assignedDriverId']?.toString().trim() ??
      rideData['driverId']?.toString().trim() ??
      '';

  bool _shouldOfferRideToDriver(
    Map<String, dynamic> rideData,
    String driverId,
  ) {
    final rideId = _rideIdFromData(rideData);
    if (rideId.isEmpty) return false;

    // Never show explicitly ignored rides
    if (_ignoredRideIds.contains(rideId)) return false;

    final rawNotInterested = rideData['notInterestedDrivers'];
    final List<String> notInterested = [];
    if (rawNotInterested is List) {
      notInterested.addAll(rawNotInterested.map((e) => e.toString()));
    }
    if (notInterested.contains(driverId)) return false;

    final assigned = _assignedDriverIdFromData(rideData);
    if (assigned.isNotEmpty && assigned != driverId) return false;

    if (_shownRideIds.contains(rideId)) {
      debugPrint('â­ï¸ Already shown this session: $rideId');
      return false;
    }

    final status = RideStatus.normalize(rideData['status']?.toString());
    if (!RideStatus.isDriverAssignable(status)) return false;

    // Apply 15 km Radius filter between driver's current position and ride pickup
    final pickupLatVal =
        rideData['pickupLat'] ??
        rideData['pickupLatitude'] ??
        rideData['pickup_lat'];
    final pickupLngVal =
        rideData['pickupLng'] ??
        rideData['pickupLongitude'] ??
        rideData['pickup_lng'];
    if (_currentLatLng != null &&
        pickupLatVal != null &&
        pickupLngVal != null) {
      final pLat = double.tryParse(pickupLatVal.toString());
      final pLng = double.tryParse(pickupLngVal.toString());
      if (pLat != null && pLng != null) {
        final distanceMeters = Geolocator.distanceBetween(
          _currentLatLng!.latitude,
          _currentLatLng!.longitude,
          pLat,
          pLng,
        );
        if (distanceMeters > 15000) {
          debugPrint(
            'â­ï¸ Ride $rideId is too far (${(distanceMeters / 1000).toStringAsFixed(1)} km). Max limit 15 km.',
          );
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> _presentRideRequest(
    Map<String, dynamic> rideData,
    String driverId, {
    bool isAssigned = false,
  }) async {
    if (_isShowingRequestScreen) {
      debugPrint(
        '[POLL] Request screen already active, skipping presentation of rideData',
      );
      return false;
    }

    final normalized = ApiService.normalizeDriverRidePayload(
      rideData,
      fallbackDriverId: driverId,
    );
    final rideId =
        normalized['rideId']?.toString() ?? _rideIdFromData(rideData);
    if (rideId.isEmpty) return false;

    if (_subscriptionService.isBlocked) return false;

    var pickup = normalized['pickup']?.toString().trim() ?? '';
    var destination = normalized['destination']?.toString().trim() ?? '';

    final message = rideData['message']?.toString() ?? '';
    Map<String, dynamic>? locationData;
    if (message.isNotEmpty) {
      locationData = await _parseLocationsFromMessage(message);
    }
    if (pickup.isEmpty) {
      pickup = locationData?['pickup']?.toString().trim() ?? '';
    }
    if (destination.isEmpty) {
      destination = locationData?['destination']?.toString().trim() ?? '';
    }

    // Only fetch full ride details if we're missing key fields.
    // This avoids an extra HTTP round-trip when data already came via polling.
    final needsDetailFetch =
        pickup.isEmpty ||
        destination.isEmpty ||
        (normalized['distance'] == null && normalized['distanceKm'] == null);

    if (needsDetailFetch) {
      debugPrint('ðŸ“¡ Fetching ride details for route: $rideId');
      final detailRes = await ApiService.getRide(rideId);
      if (detailRes.success) {
        final d = ApiService.normalizeDriverRidePayload(detailRes.data);
        if (pickup.isEmpty) pickup = d['pickup']?.toString() ?? '';
        if (destination.isEmpty) {
          destination = d['destination']?.toString() ?? '';
        }
        if (d['distance'] != null || d['distanceKm'] != null) {
          normalized['distance'] = d['distance'];
          normalized['distanceKm'] = d['distanceKm'];
        }
        if (d['duration'] != null || d['durationMin'] != null) {
          normalized['duration'] = d['duration'];
          normalized['durationMin'] = d['durationMin'];
        }
        if ((normalized['fare'] == null || normalized['fare'] == 0) &&
            d['fare'] != null) {
          normalized['fare'] = d['fare'];
        }
      } else if (detailRes.statusCode == 404) {
        debugPrint(
          '[POLL] Ride details fetch returned 404 for rideId: $rideId. Aborting and ignoring.',
        );
        await _markRideIgnored(rideId);
        return false;
      } else {
        debugPrint(
          '[POLL] Ride details fetch failed (status=${detailRes.statusCode}) for rideId: $rideId. Skipping tick.',
        );
        return false;
      }
    }

    if (pickup.isEmpty) pickup = 'Pickup location';
    if (destination.isEmpty) destination = 'Drop location';

    await _markRideAsShown(rideId, driverId);

    var distance = ApiService.formatDistanceDisplay(
      normalized['distance'] ?? normalized['distanceKm'],
    );
    if (distance == '—') {
      distance = ApiService.formatDistanceDisplay(rideData['distance']);
    }
    if (distance == '—') {
      distance = ApiService.formatDistanceDisplay(rideData['distanceKm']);
    }

    var duration = ApiService.formatDurationDisplay(
      normalized['duration'] ?? normalized['durationMin'],
    );
    if (duration == '—') {
      duration = ApiService.formatDurationDisplay(rideData['duration']);
    }
    if (duration == '—') {
      duration = ApiService.formatDurationDisplay(rideData['durationMin']);
    }

    final rideType =
        normalized['rideType']?.toString() ??
        rideData['rideType']?.toString() ??
        _vehicleType;
    var fare =
        normalized['fare']?.toString() ??
        rideData['fare']?.toString() ??
        rideData['price']?.toString() ??
        rideData['estimatedFare']?.toString() ??
        rideData['total']?.toString() ??
        '';
    if (fare.isEmpty) {
      fare = locationData?['fare']?.toString() ?? '';
    }

    _pollTimer?.cancel();
    setState(() {
      _isOnline = false;
      _isShowingRequestScreen = true;
    });

    if (!mounted) return false;

    String? result;
    try {
      result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => RideRequestScreen(
            rideId: rideId,
            pickup: pickup,
            destination: destination,
            distance: distance,
            rideType: rideType,
            duration: duration,
            fare: fare.isEmpty ? null : fare,
            isAssigned: isAssigned,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isShowingRequestScreen = false);
      }
    }

    if (!mounted) return true;

    if (result == 'completed') {
      await _syncDashboardData();
      _shownRideIds.clear();
      await ShownRidesStorage.clear();
    } else if (result == 'interested') {
      // Driver declared interest — remove from ignored so the ride proceeds
      _unmarkRideIgnored(rideId);
      setState(() {
        _isOnline = true;
        _waitingRides[rideId] = normalized;
        _interestReflected = false;
        _waitingCheckTickCount = 0; // Reset throttle counter on new interest
      });
      _startPolling();
      _performPollingTick();
    } else {
      // Driver declined or timer expired
      await _markRideIgnored(rideId);
      ApiService.rejectRide(rideId: rideId, driverId: driverId).then((res) {
        debugPrint(
          res.success
              ? 'âœ… [REJECT] rejectRide succeeded'
              : 'âš ï¸ [REJECT] rejectRide failed: ${res.errorMessage}',
        );
      });
      unawaited(_markDriverNotInterested(rideId, driverId));

      if (mounted) {
        setState(() => _isOnline = true);
        _startPolling();
      }
    }
    return true;
  }

  /// Extract human-readable location names from a notification message.
  ///
  /// Example input:
  ///   "A user assigned you a new ride from Lat: 30.31479, Lng: 78.03401 to Lat: 30.31372, Lng: 78.03590"
  ///
  /// When "Lat: X, Lng: Y" coordinates are found they are reverse-geocoded to
  /// a readable address via [GeocodingService].
  Future<Map<String, dynamic>?> _parseLocationsFromMessage(
    String message,
  ) async {
    try {
      // Extract the "from … to" section
      final fromMatch = RegExp(
        r'from\s+(.*?)\s+to',
        caseSensitive: false,
      ).firstMatch(message);

      final toMatch = RegExp(
        r'\bto\s+(.*)$',
        caseSensitive: false,
      ).firstMatch(message);

      String pickup = fromMatch?.group(1)?.trim() ?? '';
      String destination = toMatch?.group(1)?.trim() ?? '';

      // Remove any trailing fare info from destination
      destination = destination.replaceAll(RegExp(r'\.\s*Fare:.*$'), '').trim();

      // Reverse-geocode coordinate strings to human-readable names
      if (pickup.isNotEmpty) {
        pickup = await GeocodingService.resolveIfCoordinates(
          pickup,
          fallback: 'Pickup Location',
        );
      } else {
        pickup = 'Pickup Location';
      }

      if (destination.isNotEmpty) {
        destination = await GeocodingService.resolveIfCoordinates(
          destination,
          fallback: 'Drop Location',
        );
      } else {
        destination = 'Drop Location';
      }

      // Extract fare (e.g. "Fare: â‚¹500")
      final fareMatch = RegExp(r'Fare:\s*[â‚¹$]?([\d.]+)').firstMatch(message);
      final fare = fareMatch?.group(1);

      return {'pickup': pickup, 'destination': destination, 'fare': fare};
    } catch (e) {
      debugPrint('WARNING Error parsing message: $e');
      return null;
    }
  }

  Map<String, Map<String, dynamic>> _waitingRides = {};
  bool _interestReflected = false;

  /// Called when driver declines or ignores a ride request.
  /// Adds driverId to backend `notInterestedDrivers` so the ride is never
  /// offered to this driver again, and saves the rideId in local storage
  /// so re-showing is prevented even across polling restarts.
  Future<void> _markDriverNotInterested(String rideId, String driverId) async {
    if (rideId.isEmpty || driverId.isEmpty) return;
    try {
      debugPrint(
        'ðŸš« [DECLINE] Marking not-interested: rideId=$rideId driverId=$driverId',
      );
      final res = await ApiService.getRide(rideId);
      if (!res.success) return;

      final data = ApiService.unwrapRidePayload(res.data);

      final List<dynamic> notInterested = List.from(
        data['notInterestedDrivers'] ?? [],
      );
      if (!notInterested.contains(driverId)) {
        notInterested.add(driverId);
      }

      // Also remove from interestedDrivers (safety cleanup)
      final List<dynamic> interested = List.from(
        data['interestedDrivers'] ?? [],
      );
      interested.remove(driverId);

      await ApiService.patchRide(
        rideId: rideId,
        fields: {
          'interestedDrivers': interested,
          'notInterestedDrivers': notInterested,
        },
      );
      debugPrint('âœ… [DECLINE] Backend updated for rideId=$rideId');
    } catch (e) {
      debugPrint('âš ï¸ [DECLINE] Could not update backend: $e');
    }
  }

  Future<void> _cancelInterest(String rideId) async {
    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) return;

    setState(() {
      _waitingRides.remove(rideId);
    });

    // Ignore this ride locally so it doesn't auto-recover before backend updates
    await _markRideIgnored(rideId);

    try {
      // Call dedicated cancel interest API
      await ApiService.cancelDriverInterest(rideId: rideId, driverId: driverId);

      // Best-effort cleanup on ride record
      final res = await ApiService.getRide(rideId);
      if (res.success) {
        final data = res.data;
        final List<dynamic> interested = List.from(
          data['interestedDrivers'] ?? [],
        );
        if (interested.contains(driverId)) {
          interested.remove(driverId);
          final List<dynamic> notInterested = List.from(
            data['notInterestedDrivers'] ?? [],
          );
          if (!notInterested.contains(driverId)) {
            notInterested.add(driverId);
          }
          await ApiService.patchRide(
            rideId: rideId,
            fields: {
              'interestedDrivers': interested,
              'notInterestedDrivers': notInterested,
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error cancelling interest: $e');
    }
  }

  bool _shouldPresentBroadcastRide(Map<String, dynamic> ride, String driverId) {
    final rideId = _rideIdFromData(ride);
    if (rideId.isEmpty) return false;

    // Check status - only requested or pending or new
    final status = RideStatus.normalize(ride['status']?.toString());
    if (status != 'requested' && status != 'pending' && status != 'new') {
      return false;
    }

    // Check vehicle type
    final rideType =
        ride['rideType']?.toString() ?? ride['vehicleType']?.toString() ?? '';
    if (rideType.isEmpty || !_doesVehicleTypeMatch(rideType, _vehicleType)) {
      return false;
    }

    // Check if already interested or not interested
    final rawInterested = ride['interestedDrivers'];
    final List<String> interested = [];
    if (rawInterested is List) {
      interested.addAll(rawInterested.map((e) => e.toString()));
    }
    if (interested.contains(driverId)) return false;

    final rawNotInterested = ride['notInterestedDrivers'];
    final List<String> notInterested = [];
    if (rawNotInterested is List) {
      notInterested.addAll(rawNotInterested.map((e) => e.toString()));
    }
    if (notInterested.contains(driverId)) return false;

    if (_shownRideIds.contains(rideId)) return false;
    if (_ignoredRideIds.contains(rideId)) return false;

    // Filter out very old rides (e.g., older than 5 minutes)
    final createdAt = _parseRequestCreatedAt(ride);
    if (createdAt != null) {
      final age = DateTime.now().difference(createdAt);
      if (age.inMinutes > 5) {
        debugPrint(
          '⏳ Broadcast Ride $rideId is too old (${age.inMinutes} mins). Ignoring.',
        );
        return false;
      }
    }

    // Apply 15 km Radius filter between driver's current position and ride pickup
    final pickupLatVal =
        ride['pickupLat'] ?? ride['pickupLatitude'] ?? ride['pickup_lat'];
    final pickupLngVal =
        ride['pickupLng'] ?? ride['pickupLongitude'] ?? ride['pickup_lng'];
    if (_currentLatLng != null &&
        pickupLatVal != null &&
        pickupLngVal != null) {
      final pLat = double.tryParse(pickupLatVal.toString());
      final pLng = double.tryParse(pickupLngVal.toString());
      if (pLat != null && pLng != null) {
        final distanceMeters = Geolocator.distanceBetween(
          _currentLatLng!.latitude,
          _currentLatLng!.longitude,
          pLat,
          pLng,
        );
        if (distanceMeters > 15000) {
          debugPrint(
            'â­ï¸ Broadcast Ride $rideId is too far (${(distanceMeters / 1000).toStringAsFixed(1)} km). Max limit 15 km.',
          );
          return false;
        }
      }
    }

    return true;
  }

  bool _doesVehicleTypeMatch(String selectedType, String driverVehicleType) {
    final sel = selectedType.toLowerCase().trim();
    final drv = driverVehicleType.toLowerCase().trim();
    if (sel == drv) return true;
    if (sel == 'bike') return drv.contains('bike');
    if (sel == 'auto') return drv.contains('auto') && !drv.contains('sedan');
    if (sel == 'ev') return drv.contains('ev');
    if (sel == 'car') return drv.contains('car') || drv.contains('sedan');
    if (sel == 'luxury') return drv.contains('luxury') || drv.contains('sedan');
    if (sel == 'suv') return drv.contains('suv');
    return false;
  }

  Future<void> _performPollingTick() async {
    if (!mounted || !_isOnline) {
      debugPrint('Polling skipped: mounted=$mounted, online=$_isOnline');
      return;
    }
    // Guard: skip if a previous tick is still running
    if (_isPolling) {
      debugPrint('â³ Polling tick skipped — previous tick still running');
      return;
    }
    _isPolling = true;

    try {
      // Moved driverId check INSIDE try so finally always resets _isPolling
      final driverId = await SessionService.getDriverId();
      if (driverId == null || driverId.isEmpty) {
        debugPrint('ERROR No driver ID');
        return;
      }

      // â”€â”€ Step 1: If we are already waiting for a ride confirmation â”€â”€
      if (_waitingRides.isNotEmpty) {
        // Throttle: only call getRide every 3rd tick (~15–30 s) to reduce spam
        _waitingCheckTickCount++;
        if (_waitingCheckTickCount % 3 != 0) {
          debugPrint(
            '⏳ Waiting tick $_waitingCheckTickCount — skipping getRide, next check at tick ${_waitingCheckTickCount + (3 - _waitingCheckTickCount % 3)}',
          );
        } else {
          final keys = _waitingRides.keys.toList();
          for (final rideId in keys) {
            final res = await ApiService.getRide(rideId);
            if (res.success && res.data.isNotEmpty) {
              final ride = ApiService.unwrapRidePayload(res.data);
              final status = RideStatus.normalize(ride['status']?.toString());
              final assignedDriverId =
                  ride['driverId']?.toString() ??
                  ride['assignedDriverId']?.toString() ??
                  '';

              if (assignedDriverId == driverId) {
                // The passenger confirmed us! Show an accept/decline popup
                debugPrint(
                  '🎯 User assigned ride $rideId to us! Showing confirmation popup...',
                );

                setState(() {
                  _waitingRides.remove(rideId);
                  _isOnline = false;
                  _isShowingRequestScreen = true;
                });
                _pollTimer?.cancel();

                final pickup =
                    ride['pickupLocation']?.toString() ??
                    ride['pickup']?.toString() ??
                    'Pickup';
                final destination =
                    ride['dropoffLocation']?.toString() ??
                    ride['destination']?.toString() ??
                    'Destination';
                final rType =
                    ride['rideType']?.toString() ??
                    ride['vehicleType']?.toString() ??
                    _vehicleType;
                final dist = ApiService.formatDistanceDisplay(
                  ride['distance'] ?? ride['distanceKm'],
                );
                final dur = ApiService.formatDurationDisplay(
                  ride['duration'] ?? ride['durationMin'],
                );
                final fareNum = ApiService.resolveRideFare(ride);
                final fare = fareNum?.toString();

                if (!mounted) return;

                String? result;
                try {
                  result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RideRequestScreen(
                        rideId: rideId,
                        pickup: pickup,
                        destination: destination,
                        rideType: rType,
                        distance: dist != '—' ? dist : '—',
                        duration: dur != '—' ? dur : '—',
                        fare: fare,
                        isAssigned: true,
                      ),
                    ),
                  );
                } finally {
                  if (mounted) setState(() => _isShowingRequestScreen = false);
                }

                if (!mounted) return;

                if (result == 'interested' || result == 'accepted') {
                  debugPrint('✅ [ACCEPT] Calling acceptRide API for $rideId');
                  ApiService.acceptRide(
                    rideId: rideId,
                    driverId: driverId,
                    distance: dist != '—' ? dist : null,
                    distanceKm: ApiService.parseDistanceKm(
                      ride['distanceKm'] ?? ride['distance'],
                    ),
                    duration: dur != '—' ? dur : null,
                    durationMin: ApiService.parseDurationMin(
                      ride['durationMin'] ?? ride['duration'],
                    ),
                  ).then((res) {
                    debugPrint(
                      res.success
                          ? '✅ [ACCEPT] acceptRide succeeded'
                          : '⚠️ [ACCEPT] acceptRide failed: ${res.errorMessage}',
                    );
                  });

                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DriverActiveRideScreen(
                          rideId: rideId,
                          pickup: pickup,
                          destination: destination,
                          rideType: rType,
                          distance: dist != '—' ? dist : '—',
                          duration: dur != '—' ? dur : '—',
                          fare: fare,
                        ),
                      ),
                    ).then((_) {
                      if (mounted) {
                        setState(() => _isOnline = true);
                        _startPolling();
                      }
                    });
                  }
                } else {
                  debugPrint('❌ Driver declined the final assignment.');
                  await _markRideIgnored(rideId);
                  ApiService.rejectRide(
                    rideId: rideId,
                    driverId: driverId,
                  ).then((res) {});
                  unawaited(_markDriverNotInterested(rideId, driverId));
                  if (mounted) {
                    setState(() => _isOnline = true);
                    _startPolling();
                  }
                }
                return; // End poll tick since we navigated
              }

              final List<dynamic> interested = List.from(
                ride['availableDrivers'] ?? ride['interestedDrivers'] ?? [],
              );
              final isInterested = interested
                  .map((e) => e.toString())
                  .contains(driverId);

              if (!isInterested && assignedDriverId != driverId) {
                debugPrint(
                  '⏸️ Driver is no longer in the interested list for $rideId. Clearing waiting state.',
                );
                setState(() => _waitingRides.remove(rideId));
              } else if (assignedDriverId.isNotEmpty &&
                  assignedDriverId != driverId) {
                debugPrint(
                  '⏸️ Ride $rideId was assigned to another driver. Clearing waiting state.',
                );
                setState(() => _waitingRides.remove(rideId));
              } else if (status == 'cancelled' || status == 'completed') {
                debugPrint(
                  '⏸️ Ride $rideId status changed to $status. Clearing waiting state.',
                );
                setState(() => _waitingRides.remove(rideId));
              } else {
                setState(() => _waitingRides[rideId] = ride);
              }
            } else {
              debugPrint(
                '⏸️ getRide failed (status=${res.statusCode}). Clearing waiting state for $rideId.',
              );
              if (res.statusCode == 404) await _markRideIgnored(rideId);
              setState(() => _waitingRides.remove(rideId));
            }
          }
        }
      }

      // Step 2: Leave local queued rides in the queue so they appear in the dashboard list.
      // We no longer auto-popup `RideRequestScreen` for them.

      // ── Step 3: Check for broadcasted unassigned rides in the system ──
      // NOTE: fetchPendingAssignmentsForDriver is intentionally NOT called here.
      // It returns ALL historical notifications (100+) and triggers a GET /rides
      // call for each one — causing a cascade of 404s.
      // Real-time assigned rides arrive via FCM (_handleRideAssignedPush).
      // Unassigned broadcast rides come from getPendingRides below.
      if (true) {
        // Always fetch broadcast rides to auto-populate _waitingRides on restart
        final zoneId = await SessionService.getZoneId();
        final broadcastRes = await ApiService.getPendingRides(zoneId: zoneId);
        if (broadcastRes.success && mounted && _isOnline) {
          final pendingList =
              broadcastRes.data['rides'] as List<dynamic>? ??
              broadcastRes.data['data'] as List<dynamic>? ??
              <dynamic>[];

          for (final item in pendingList) {
            if (item is! Map<String, dynamic>) continue;

            final rId = _rideIdFromData(item);
            if (rId.isEmpty) continue;

            final interestedList = List.from(
              item['availableDrivers'] ?? item['interestedDrivers'] ?? [],
            );
            if (interestedList.map((e) => e.toString()).contains(driverId)) {
              if (!_waitingRides.containsKey(rId) &&
                  !_ignoredRideIds.contains(rId)) {
                debugPrint('🔄 Auto-recovering interested ride: $rId');
                setState(() {
                  _waitingRides[rId] = item;
                });
              }
              continue; // Already interested, skip local popup queue
            }
            if (_shouldPresentBroadcastRide(item, driverId)) {
              debugPrint(
                '🎯 Broadcasted unassigned ride matches: $rId, adding to local queue',
              );
              // Instead of popping up, just add to the queue so it shows in the list
              RideRequestService.queueRideRequest(item);
            }
          }
        }
      }
      // ── Step 4: Show popup for unassigned queued rides if not already showing one ──
      debugPrint(
        'STEP 4: _isShowingRequestScreen=$_isShowingRequestScreen, _waitingRides=${_waitingRides.length}, _isOnline=$_isOnline',
      );
      if (!_isShowingRequestScreen &&
          _waitingRides.isEmpty &&
          mounted &&
          _isOnline) {
        final localRides = RideRequestService.pendingRequests;
        debugPrint(
          'STEP 4: Checking ${localRides.length} local rides for popup',
        );
        for (final ride in localRides) {
          final rId = _rideIdFromData(ride);
          debugPrint(
            'STEP 4 loop: rideId=$rId, isIgnored=${_ignoredRideIds.contains(rId)}',
          );
          if (rId.isEmpty || _ignoredRideIds.contains(rId)) continue;
          if (_isShowingRequestScreen) break; // Double check
          if (_waitingRides.containsKey(rId)) {
            continue; // Already interested
          }

          // Claim screen synchronously before await
          setState(() => _isShowingRequestScreen = true);

          try {
            // Found an unassigned ride that hasn't been ignored locally. Show popup instantly.
            // We do not await ApiService.enrichRideWithRouteDetails here because
            // RideRequestScreen already fetches getRide() in its initState().
            if (!mounted) return;

            final pickup =
                ride['pickupLocation']?.toString() ??
                ride['pickup']?.toString() ??
                'Pickup';
            final destination =
                ride['dropoffLocation']?.toString() ??
                ride['destination']?.toString() ??
                'Destination';
            final rType =
                ride['rideType']?.toString() ??
                ride['vehicleType']?.toString() ??
                _vehicleType;
            final dist = ApiService.formatDistanceDisplay(
              ride['distance'] ?? ride['distanceKm'],
            );
            final dur = ApiService.formatDurationDisplay(
              ride['duration'] ?? ride['durationMin'],
            );
            final fareNum = ApiService.resolveRideFare(ride);
            final fare = fareNum?.toString();

            String? result;
            result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => RideRequestScreen(
                  rideId: rId,
                  pickup: pickup,
                  destination: destination,
                  rideType: rType,
                  distance: dist != '—' ? dist : '—',
                  duration: dur != '—' ? dur : '—',
                  fare: fare,
                  isAssigned:
                      false, // It's a broadcast ride, so driver decides if interested
                ),
              ),
            );

            if (!mounted) return;

            if (result == 'interested') {
              // Driver expressed interest! The RideRequestScreen already called declareDriverAvailable API.
              // We just set our state to wait for the user to assign.
              setState(() {
                _waitingRides[rId] = ride;
                _interestReflected = true;
                _waitingCheckTickCount = 0;
              });
              break;
            } else {
              // Driver hit ignore, or timer expired, or back button.
              // Mark it ignored locally so it doesn't pop up again.
              await _markRideIgnored(rId);
              RideRequestService.removeRequestByRideId(rId);
              
              // Hit the API so backend knows this broadcast was ignored by this driver
              ApiService.ignoreBroadcastRide(rideId: rId, driverId: driverId)
                  .then((res) {
                if (res.success) {
                  debugPrint('✅ [IGNORE] Successfully ignored broadcast $rId');
                } else {
                  debugPrint('⚠️ [IGNORE] Failed to ignore broadcast: ${res.errorMessage}');
                }
              });

              break; // Stop popping up back-to-back to give driver a breather
            }
          } finally {
            if (mounted) setState(() => _isShowingRequestScreen = false);
          }
        }
      }
    } catch (e) {
      debugPrint('ERROR Polling error: $e');
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _updateStatusOnServer(bool online) async {
    final driverId = await SessionService.getDriverId();
    if (driverId != null && driverId.isNotEmpty) {
      await ApiService.updateDriverStatus(
        driverId: driverId,
        status: online ? 'online' : 'offline',
        available: online,
      );
    }
  }

  void _onRideComplete(Map<String, dynamic> request) {
    final distStr = request['distance'] as String? ?? '0 km';
    final distVal =
        double.tryParse(distStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final norm = ApiService.normalizeDriverRidePayload(request);
    final riderName = norm['riderName']?.toString() ?? '';
    setState(() {
      _isOnline = false;
      _completedTrips++;
      _totalDistanceKm += distVal;
      _subscriptionService.updatePerformanceDistance(_totalDistanceKm);
      _tripHistory.insert(0, {
        'pickup': request['pickup'],
        'destination': request['destination'],
        'rideType': request['rideType'],
        'distance': request['distance'],
        'duration': request['duration'],
        'date': _formatDate(DateTime.now()),
        'time': _formatTime(DateTime.now()),
        'riderName': riderName,
        'passengerName': riderName,
        'startTime':
            request['startTime']?.toString() ?? _formatTime(DateTime.now()),
        'endTime':
            request['endTime']?.toString() ?? _formatTime(DateTime.now()),
        'fare': () {
          final rawFare =
              request['fare']?.toString() ??
              request['price']?.toString() ??
              '—';
          return rawFare == '—'
              ? '—'
              : rawFare.replaceAll(RegExp(r'[^0-9.]'), '');
        }(),
        'rating': '—',
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    _updateStatusOnServer(false);
    _pollTimer?.cancel(); // Ensure polling is stopped when ride completes
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionService.removeListener(_onSubscriptionChanged);
    _fcmSubscription?.cancel();
    _pollTimer?.cancel();
    _currentRideTimer?.cancel();
    _dashboardSyncTimer?.cancel();
    globalPendingRideAction.removeListener(_onPendingRideActionChanged);
    _positionSubscription?.cancel();
    // Best-effort: try to mark offline when widget is disposed.
    _markDriverOffline(); // ignore: unawaited_futures
    super.dispose();
  }

  // â”€â”€ Theme helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Color _surface(bool isDark) =>
      isDark ? AppColors.darkSurface : AppColors.surface;
  Color _cardSoft(bool isDark) =>
      isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
  Color _border(bool isDark) =>
      isDark ? AppColors.darkBorder : AppColors.border;
  Color _textPri(bool isDark) =>
      isDark ? AppColors.darkOnSurface : AppColors.textDark;
  Color _textSec(bool isDark) =>
      isDark ? AppColors.darkOnSurface.withAlpha(160) : AppColors.textGrey;

  Widget _buildDriverMap(
    BuildContext context,
    bool isDark,
    Color surface,
    Color border,
  ) {
    if (!_supportsMap) {
      return const SizedBox.shrink();
    }

    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;

    return GlassCard(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(12),
      color: surface,
      border: Border.all(color: border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.map_rounded, color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your Location',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: _currentLatLng == null
                  ? const Center(child: CircularProgressIndicator())
                  : FutureBuilder<BitmapDescriptor>(
                      future: MapUtils.get3DVehicleMarkerForType(_vehicleType),
                      builder: (context, snapshot) {
                        final markerIcon =
                            snapshot.data ?? BitmapDescriptor.defaultMarker;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: _currentLatLng!,
                                  zoom: 16.0,
                                  tilt: 0.0,
                                ),
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                },
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                zoomControlsEnabled: false,
                                gestureRecognizers:
                                    <Factory<OneSequenceGestureRecognizer>>{
                                      Factory<OneSequenceGestureRecognizer>(
                                        () => EagerGestureRecognizer(),
                                      ),
                                    }.toSet(),
                                markers: {
                                  Marker(
                                    markerId: const MarkerId(
                                      'driver_current_location',
                                    ),
                                    position: _currentLatLng!,
                                    icon: markerIcon,
                                    flat: false,
                                    anchor: const Offset(0.5, 0.5),
                                    infoWindow: InfoWindow(
                                      title: 'Your Location ($_vehicleType)',
                                      snippet: _vehicleModel.isNotEmpty
                                          ? '$_vehicleModel${_vehicleNumber.isNotEmpty ? " • $_vehicleNumber" : ""}'
                                          : _driverName,
                                    ),
                                  ),
                                },
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 14,
                              child: GlassCard(
                                borderRadius: BorderRadius.circular(16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                color: Theme.of(
                                  context,
                                ).cardColor.withValues(alpha: 0.88),
                                border: Border.all(
                                  color: AppColors.surfaceLight,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: AppColors.accentStrong,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Live map',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              right: 14,
                              child: GestureDetector(
                                onTap: () {
                                  if (_mapController != null &&
                                      _currentLatLng != null) {
                                    _mapController!.animateCamera(
                                      CameraUpdate.newLatLng(_currentLatLng!),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).cardColor.withValues(alpha: 0.88),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surfaceLight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(20),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.my_location,
                                    color: AppColors.accentStrong,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 64,
                              right: 14,
                              child: GestureDetector(
                                onTap: () {
                                  if (_mapController != null) {
                                    _mapController!.animateCamera(
                                      CameraUpdate.zoomIn(),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).cardColor.withValues(alpha: 0.88),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surfaceLight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(20),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: AppColors.accentStrong,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 114,
                              right: 14,
                              child: GestureDetector(
                                onTap: () {
                                  if (_mapController != null) {
                                    _mapController!.animateCamera(
                                      CameraUpdate.zoomOut(),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).cardColor.withValues(alpha: 0.88),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surfaceLight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(20),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.remove,
                                    color: AppColors.accentStrong,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = _surface(isDark);
    final cardSoft = _cardSoft(isDark);
    final border = _border(isDark);
    final textPri = _textPri(isDark);
    final textSec = _textSec(isDark);
    final green = AppColors.secondary;
    final queued = _matchingRequests;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              borderRadius: BorderRadius.circular(24),
              padding: const EdgeInsets.all(20),
              color: surface,
              border: Border.all(color: border),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar (initials only, no popup)
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: green,
                        child: Text(
                          _driverName
                              .split(' ')
                              .map((s) => s.isNotEmpty ? s[0] : '')
                              .take(2)
                              .join(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Name + vehicle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Hello,',
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 16,
                                    color: textPri,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _driverName,
                                    style: AppTextStyles.heading.copyWith(
                                      fontSize: 16,
                                      color: green,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_verificationStatus == 'verified') ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.verified_rounded,
                                    color: green,
                                    size: 15,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.directions_car_outlined,
                                  size: 12,
                                  color: textSec,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _vehicleModel.isNotEmpty
                                        ? '$_vehicleModel${_vehicleNumber.isNotEmpty ? ' • $_vehicleNumber' : ''}'
                                        : _vehicleType,
                                    style: AppTextStyles.body.copyWith(
                                      fontSize: 12,
                                      color: textSec,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const ChalChalGadiLogo(size: 42),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, thickness: 0.5),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Theme toggle
                          ValueListenableBuilder<ThemeMode>(
                            valueListenable: AppTheme.themeMode,
                            builder: (ctx, mode, _) {
                              final dark =
                                  mode == ThemeMode.dark ||
                                  (mode == ThemeMode.system &&
                                      MediaQuery.of(ctx).platformBrightness ==
                                          Brightness.dark);
                              return InkWell(
                                onTap: AppTheme.toggleMode,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: border),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    dark
                                        ? Icons.wb_sunny_rounded
                                        : Icons.nights_stay_rounded,
                                    color: green,
                                    size: 20,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),

                          // Language toggle
                          LanguageToggleButton(
                            style: LanguageToggleStyle.outlined,
                            color: green,
                            borderColor: border,
                          ),
                          const SizedBox(width: 12),

                          // Refresh button
                          InkWell(
                            onTap: _refreshDashboard,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(color: border),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.refresh_rounded,
                                color: green,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Online toggle
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _isOnline ? 'Duty On' : 'Duty Off',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? green : AppColors.accentRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: _isOnline,
                            activeThumbColor: green,
                            activeTrackColor: green.withAlpha(120),
                            onChanged: _toggleOnline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // â”€â”€ Verification Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _buildVerificationCard(
              surface: surface,
              border: border,
              textPri: textPri,
              textSec: textSec,
              green: green,
              isDark: isDark,
            ),

            // â”€â”€ Status banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            GlassCard(
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.all(20),
              color: _isOnline ? green.withAlpha(isDark ? 40 : 20) : cardSoft,
              border: Border.all(
                color: _isOnline ? green.withAlpha(120) : border,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isOnline ? green.withAlpha(40) : surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: _isOnline ? green : textSec,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOnline ? 'You are online' : 'You are offline',
                          style: AppTextStyles.heading.copyWith(
                            fontSize: 17,
                            color: textPri,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isOnline
                              ? 'Waiting for a $_vehicleType ride request...'
                              : 'Toggle online to start receiving rides.',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13,
                            color: textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_activeRide != null) ...[
              const SizedBox(height: 16),
              _buildActiveRideBanner(context),
            ],

            if (_waitingRides.isNotEmpty) const SizedBox(height: 16),
            ..._waitingRides.entries.map((entry) {
              final rideId = entry.key;
              final rideData = entry.value;
              final pickupStr =
                  (rideData['pickup'] ?? rideData['pickupLocation'] ?? 'Pickup')
                      .toString();
              final destStr =
                  (rideData['destination'] ??
                          rideData['dropoffLocation'] ??
                          'Destination')
                      .toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(12),
                  color: AppColors.accentYellow.withAlpha(isDark ? 40 : 20),
                  border: Border.all(
                    color: AppColors.accentYellow.withAlpha(120),
                    width: 1.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentYellow,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Waiting for Confirmation...',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                color: textPri,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'P: $pickupStr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: textPri,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'D: $destStr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: textPri,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final driverId =
                                    await SessionService.getDriverId();
                                if (!mounted ||
                                    driverId == null ||
                                    driverId.isEmpty ||
                                    rideId.isEmpty)
                                  return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: rideId,
                                      senderId: driverId,
                                      senderModel: 'driver',
                                      otherPartyName: 'Passenger',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('Chat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accentStrong,
                                side: BorderSide(
                                  color: AppColors.accentStrong.withAlpha(160),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                if (rideId.isNotEmpty) {
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(context);
                                  await _cancelInterest(rideId);
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Interest cancelled.'),
                                      backgroundColor: AppColors.accentRed,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 16),
                              label: const Text('Cancel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accentRed,
                                side: BorderSide(
                                  color: AppColors.accentRed.withAlpha(160),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 16),

            _buildDriverMap(context, isDark, surface, border),

            const SizedBox(height: 16),

            // â”€â”€ Queued requests for this driver's vehicle type â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (queued.isNotEmpty) ...[
              Text(
                'Queued Ride Requests',
                style: AppTextStyles.heading.copyWith(
                  fontSize: 18,
                  color: textPri,
                ),
              ),
              const SizedBox(height: 10),
              ...queued.map(
                (req) => _queuedCard(
                  req,
                  surface,
                  border,
                  textPri,
                  textSec,
                  green,
                  isDark,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // â”€â”€ Promotional banners (from API) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            HomeBannerCarousel(fetchBanners: ApiService.getDriverBanners),
            const SizedBox(height: 16),

            // â”€â”€ Stats — 4 dynamic tiles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Text(
              'Performance',
              style: AppTextStyles.heading.copyWith(
                fontSize: 18,
                color: textPri,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard(
                  'Trips',
                  '$_completedTrips',
                  Icons.check_circle_outline,
                  green,
                  cardSoft,
                  textPri,
                  textSec,
                ),
                const SizedBox(width: 10),
                _statCard(
                  'Distance',
                  '${_totalDistanceKm.toStringAsFixed(1)} km',
                  Icons.route_outlined,
                  AppColors.accentYellow,
                  cardSoft,
                  textPri,
                  textSec,
                ),
                const SizedBox(width: 10),
                _statCard(
                  'Rating',
                  _rating,
                  Icons.star_outline,
                  AppColors.accentRed,
                  cardSoft,
                  textPri,
                  textSec,
                ),
                const SizedBox(width: 10),
                _statCard(
                  'Exp.',
                  _experience,
                  Icons.workspace_premium_outlined,
                  AppColors.secondary,
                  cardSoft,
                  textPri,
                  textSec,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // â”€â”€ Vehicle info card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (_vehicleModel.isNotEmpty || _vehicleType.isNotEmpty) ...[
              Text(
                'Your Vehicle',
                style: AppTextStyles.heading.copyWith(
                  fontSize: 18,
                  color: textPri,
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(18),
                color: surface,
                border: Border.all(color: border),
                child: Row(
                  children: [
                    // Category image from API (falls back to emoji)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: green.withAlpha(25),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CategoryVehicleImage(
                          vehicleType: _vehicleType,
                          size: 56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vehicleModel.isNotEmpty
                                ? _vehicleModel
                                : _vehicleType,
                            style: AppTextStyles.heading.copyWith(
                              fontSize: 16,
                              color: textPri,
                            ),
                          ),
                          if (_vehicleNumber.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _vehicleNumber,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: textSec,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: green.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: green.withAlpha(80)),
                      ),
                      child: Text(
                        _vehicleType,
                        style: TextStyle(
                          fontSize: 12,
                          color: green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRideBanner(BuildContext context) {
    if (_activeRide == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark
        ? AppColors.darkOnSurface
        : AppColors.textDark;

    final rideData = _activeRide!.raw;
    final pickupStr =
        rideData['pickupLocation']?.toString() ??
        rideData['pickupAddress']?.toString() ??
        'Pickup location';
    final destStr =
        rideData['dropoffLocation']?.toString() ??
        rideData['destinationAddress']?.toString() ??
        'Destination';
    final statusStr = _activeRide!.status.toLowerCase();

    String? passengerName;
    if (rideData['user'] != null && rideData['user'] is Map) {
      passengerName = rideData['user']['name']?.toString();
    }
    final titleText = (passengerName != null && passengerName.isNotEmpty)
        ? 'Ride with $passengerName'
        : 'Active Ride in Progress';

    String readableStatus = 'Active ride';
    if (statusStr == 'assigned') {
      readableStatus = 'Ride assigned to you';
    } else if (statusStr == 'accepted') {
      readableStatus = 'Heading to pickup';
    } else if (statusStr == 'ongoing' || statusStr == 'started') {
      readableStatus = 'Trip in progress';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkSurfaceSoft, AppColors.darkSurface]
              : [AppColors.surfaceSoft, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.accentStrong.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentStrong.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentStrong.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: AppColors.accentStrong,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: AppTextStyles.cardTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            readableStatus,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentStrong,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Route info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceSoft.withValues(alpha: 0.5)
                  : AppColors.surfaceSoft.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      size: 14,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickupStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1, indent: 22),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: AppColors.accentRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        destStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CustomButton(
              label: 'Resume Navigation',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverActiveRideScreen(
                      rideId: _activeRide!.id,
                      pickup: pickupStr,
                      destination: destStr,
                      rideType:
                          rideData['rideType']?.toString() ??
                          rideData['vehicleType']?.toString() ??
                          'bike',
                      distance: '-',
                      duration: '-',
                    ),
                  ),
                );
              },
              color: AppColors.accentStrong,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget bodyWidget;
    switch (_bottomNavIndex) {
      case 1:
        bodyWidget = DriverTripsHistoryScreen(tripHistory: _tripHistory);
        break;
      case 2:
        bodyWidget = DriverProfileScreen(
          isOnline: _isOnline,
          onOnlineToggle: _toggleOnline,
          onLogout: _logout,
        );
        break;
      default:
        bodyWidget = _buildHomeContent(context);
        break;
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: bodyWidget,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) {
          setState(() {
            _bottomNavIndex = index;
          });
          if (index == 0) {
            _syncDashboardData();
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.accentStrong,
        unselectedItemColor: AppColors.textGrey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_rounded),
            label: context.tr('home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_rounded),
            label: context.tr('trips'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_rounded),
            label: context.tr('profile'),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Queued request card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _queuedCard(
    Map<String, dynamic> req,
    Color surface,
    Color border,
    Color textPri,
    Color textSec,
    Color green,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () async {
        final driverId = await SessionService.getDriverId();
        if (driverId != null && driverId.isNotEmpty) {
          _presentRideRequest(req, driverId, isAssigned: false);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: green.withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 40 : 8),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req['pickup'] as String,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textPri,
                    ),
                  ),
                ),
                _chip(req['rideType'] as String, green, isDark),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.accentRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    req['destination'] as String,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      color: textSec,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _infoChip(
                  Icons.straighten,
                  req['distance'] as String,
                  textSec,
                  border,
                ),
                const SizedBox(width: 8),
                _infoChip(
                  Icons.access_time,
                  req['duration'] as String,
                  textSec,
                  border,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color green, bool isDark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: green.withAlpha(30),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: green.withAlpha(80)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: green, fontWeight: FontWeight.w700),
    ),
  );

  Widget _infoChip(IconData icon, String label, Color textSec, Color border) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.secondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: textSec,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color accent,
    Color cardSoft,
    Color textPri,
    Color textSec,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: cardSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTextStyles.heading.copyWith(
                fontSize: 16,
                color: textPri,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.body.copyWith(fontSize: 10, color: textSec),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case 'Bike':
        return Icons.two_wheeler;
      case 'Auto':
        return Icons.electric_rickshaw;
      case 'Cab Economy':
        return Icons.directions_car;
      case 'Cab Prime':
        return Icons.local_taxi;
      case 'Cab XL':
        return Icons.airport_shuttle;
      default:
        return Icons.directions_car;
    }
  }

  // â”€â”€ Verification UI Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showVerificationWarning() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surface = _surface(isDark);
        final textPri = _textPri(isDark);
        final textSec = _textSec(isDark);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: _border(isDark))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: _border(isDark),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Icon(
                _verificationStatus == 'rejected'
                    ? Icons.gpp_bad_rounded
                    : Icons.gpp_maybe_rounded,
                color: _verificationStatus == 'rejected'
                    ? AppColors.accentRed
                    : AppColors.accentYellow,
                size: 56,
              ),
              const SizedBox(height: 18),
              Text(
                _verificationStatus == 'rejected'
                    ? 'Verification Rejected'
                    : 'Verification Pending',
                style: AppTextStyles.heading.copyWith(
                  fontSize: 20,
                  color: textPri,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _verificationStatus == 'rejected'
                    ? 'Your documents were rejected: "$_rejectionReason". Please update your documents to proceed.'
                    : 'Your registration documents are currently under review. You will be able to go online once they are approved by admin.',
                style: AppTextStyles.body.copyWith(
                  fontSize: 14,
                  color: textSec,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (_verificationStatus == 'rejected')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentStrong,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showDocumentUpdateSheet();
                  },
                  child: const Text(
                    'Update Documents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _border(isDark),
                    foregroundColor: textPri,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerificationCard({
    required Color surface,
    required Color border,
    required Color textPri,
    required Color textSec,
    required Color green,
    required bool isDark,
  }) {
    if (_verificationStatus == 'verified') {
      return const SizedBox.shrink();
    }

    final isRejected = _verificationStatus == 'rejected';
    final cardColor = isRejected
        ? AppColors.accentRed.withAlpha(isDark ? 30 : 15)
        : AppColors.accentYellow.withAlpha(isDark ? 35 : 15);
    final borderColor = isRejected
        ? AppColors.accentRed.withAlpha(120)
        : AppColors.accentYellow.withAlpha(120);
    final iconColor = isRejected ? AppColors.accentRed : AppColors.accentYellow;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(20),
        color: cardColor,
        border: Border.all(color: borderColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRejected
                        ? Icons.gpp_bad_rounded
                        : Icons.gpp_maybe_rounded,
                    color: iconColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRejected
                            ? 'Verification Rejected'
                            : 'Verification Under Review',
                        style: AppTextStyles.heading.copyWith(
                          fontSize: 17,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRejected
                            ? 'Reason: "$_rejectionReason"'
                            : 'Admin is reviewing your submitted documents. It usually takes 12-24 hours to approve.',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              'Submitted Documents Status',
              style: AppTextStyles.heading.copyWith(
                fontSize: 14,
                color: textPri,
              ),
            ),
            const SizedBox(height: 12),
            _buildDocStatusItem(
              'Driving License',
              isRejected ? 'verified' : 'pending',
              isDark,
            ),
            _buildDocStatusItem(
              'Aadhaar Card (Front & Back)',
              isRejected ? 'rejected' : 'pending',
              isDark,
            ),
            _buildDocStatusItem(
              'Vehicle RC',
              isRejected ? 'verified' : 'pending',
              isDark,
            ),
            _buildDocStatusItem(
              'Insurance Policy',
              isRejected ? 'verified' : 'pending',
              isDark,
            ),
            _buildDocStatusItem(
              'Pollution Under Control (PUC)',
              isRejected ? 'verified' : 'pending',
              isDark,
            ),
            if (isRejected) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _showDocumentUpdateSheet,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text(
                  'Update Documents',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocStatusItem(String title, String status, bool isDark) {
    Color iconColor;
    IconData iconData;
    String statusText;

    if (status == 'verified') {
      iconColor = AppColors.secondary;
      iconData = Icons.check_circle_rounded;
      statusText = 'Verified';
    } else if (status == 'rejected') {
      iconColor = AppColors.accentRed;
      iconData = Icons.cancel_rounded;
      statusText = 'Needs Re-upload';
    } else {
      iconColor = AppColors.accentYellow;
      iconData = Icons.pending_rounded;
      statusText = 'Pending';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                color: isDark ? AppColors.darkOnSurface : AppColors.textDark,
              ),
            ),
          ),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: iconColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showDocumentUpdateSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        String pickedAadhaarFront = '';
        String pickedAadhaarBack = '';
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final surface = _surface(isDark);
            final textPri = _textPri(isDark);
            final textSec = _textSec(isDark);
            final borderCol = _border(isDark);

            Future<void> pickFile(bool isFront) async {
              const typeGroup = XTypeGroup(
                label: 'images',
                extensions: ['jpg', 'jpeg', 'png', 'pdf'],
              );
              final file = await openFile(acceptedTypeGroups: [typeGroup]);
              if (file != null) {
                setSheetState(() {
                  if (isFront) {
                    pickedAadhaarFront = file.name;
                  } else {
                    pickedAadhaarBack = file.name;
                  }
                });
              }
            }

            Future<void> submit() async {
              if (pickedAadhaarFront.isEmpty || pickedAadhaarBack.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please select files for both Aadhaar front and back.',
                    ),
                    backgroundColor: AppColors.accentRed,
                  ),
                );
                return;
              }

              setSheetState(() => isSubmitting = true);

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(sheetContext);

              // Simulate upload latency
              await Future.delayed(const Duration(milliseconds: 1500));

              // Update status to pending
              final driverId = await SessionService.getDriverId() ?? 'mock';
              await SessionService.saveDriver(
                id: driverId,
                name: _driverName,
                phone: _driver['phone'] ?? '',
                vehicleNumber: _vehicleNumber,
                vehicleType: _vehicleType,
                verificationStatus: 'pending',
                rejectionReason: '',
                experience: _experience,
                rating: _rating,
                vehicleModel: _vehicleModel,
              );

              // Update in-memory
              setState(() {
                DriverRepository.currentDriver = {
                  ...DriverRepository.currentDriver!,
                  'verificationStatus': 'pending',
                  'rejectionReason': '',
                };
                _isOnline = false; // ensure they remain offline
              });

              if (!mounted) return;
              navigator.pop();

              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Documents re-submitted successfully. Verification status is now Pending.',
                  ),
                  backgroundColor: AppColors.secondary,
                  duration: Duration(seconds: 4),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border(top: BorderSide(color: borderCol)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 50,
                        height: 4,
                        decoration: BoxDecoration(
                          color: borderCol,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Re-upload Documents',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 20,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select new clear copies to replace the rejected files.',
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: textSec,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Rejected item detail
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accentRed.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accentRed.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.accentRed,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Failed: Aadhaar Card (Reason: "$_rejectionReason")',
                              style: TextStyle(
                                color: AppColors.accentRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // File upload field 1: Aadhaar Front
                    Text(
                      'Aadhaar Card Front Photo',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildUploadButton(
                      fileName: pickedAadhaarFront,
                      onTap: () => pickFile(true),
                      borderCol: borderCol,
                      textPri: textPri,
                      textSec: textSec,
                    ),
                    const SizedBox(height: 16),

                    // File upload field 2: Aadhaar Back
                    Text(
                      'Aadhaar Card Back Photo',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildUploadButton(
                      fileName: pickedAadhaarBack,
                      onTap: () => pickFile(false),
                      borderCol: borderCol,
                      textPri: textPri,
                      textSec: textSec,
                    ),
                    const SizedBox(height: 28),

                    // Submit button
                    isSubmitting
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.accentStrong,
                            ),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentStrong,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: submit,
                            child: const Text(
                              'Submit Updated Documents',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUploadButton({
    required String fileName,
    required VoidCallback onTap,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol),
        ),
        child: Row(
          children: [
            Icon(
              fileName.isNotEmpty
                  ? Icons.check_circle_rounded
                  : Icons.cloud_upload_outlined,
              color: fileName.isNotEmpty
                  ? AppColors.secondary
                  : AppColors.accentStrong,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName.isNotEmpty ? fileName : 'Upload image / PDF file',
                style: TextStyle(
                  color: fileName.isNotEmpty ? textPri : textSec,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (fileName.isEmpty)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }
}
