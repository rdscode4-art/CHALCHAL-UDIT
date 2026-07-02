import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Initializes the flutter_background_service.
/// Call this from main.dart before runApp().
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'chalchalgaadi_foreground', // id
    'Driver Status', // title
    description: 'Keeps the driver app awake to receive rides.',
    importance: Importance.low, // low importance prevents sound on every update
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'chalchalgaadi_foreground',
      initialNotificationTitle: 'Chal Chal Gaadi',
      initialNotificationContent: 'You are online',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // Immediately set as foreground to prevent Android 12+ ForegroundServiceDidNotStartInTimeException
    service.setAsForegroundService();

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Explicitly update notification immediately upon starting
    service.setForegroundNotificationInfo(
      title: "Chal Chal Gaadi",
      content: "You are online",
    );
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Keep the service alive and update notification text
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Chal Chal Gaadi",
          content: "You are online",
        );
      }
    }
  });

  StreamSubscription<Position>? positionStream;
  String? driverId;

  // Function to initialize location stream once we have a driverId
  void startLocationStream() {
    if (positionStream != null) return; // Already listening
    
    final locationSettings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: "Location service is running in background",
              notificationTitle: "Chal Chal Gaadi",
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          );
    
    positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      try {
        if (driverId != null && driverId!.isNotEmpty) {
          await ApiService.updateDriverLocationOnly(
            driverId: driverId!,
            lat: position.latitude,
            lng: position.longitude,
          );
          debugPrint('🌊 [BACKGROUND_STREAM] Location updated: ${position.latitude}, ${position.longitude}');
        }
      } catch (e) {
        debugPrint('❌ [BACKGROUND_STREAM] Error updating location: $e');
      }
    });
  }

  bool _isFetchingLocation = false;

  // Periodic timer to fetch driverId if missing, and force a location update
  // just in case the stream gets suspended by the OS when screen is off.
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    try {
      if (driverId == null || driverId!.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        driverId = prefs.getString('session_id');
      }

      if (driverId != null && driverId!.isNotEmpty) {
        startLocationStream();
        
        // Prevent overlapping location requests
        if (_isFetchingLocation) return;
        _isFetchingLocation = true;

        try {
          // As a bullet-proof fallback for Doze mode, manually fetch and send location periodically.
          Position? position;
          try {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 10), // Increased to 10s
            );
          } on TimeoutException {
            debugPrint('⚠️ [BACKGROUND_TIMER] getCurrentPosition timed out. Trying last known position...');
            position = await Geolocator.getLastKnownPosition();
          }

          if (position != null) {
            await ApiService.updateDriverLocationOnly(
              driverId: driverId!,
              lat: position.latitude,
              lng: position.longitude,
            );
            debugPrint('⏱️ [BACKGROUND_TIMER] Location updated: ${position.latitude}, ${position.longitude}');
          } else {
            debugPrint('⚠️ [BACKGROUND_TIMER] Could not determine position. Will retry next tick.');
          }
        } finally {
          _isFetchingLocation = false;
        }
      }
    } catch (e) {
      _isFetchingLocation = false;
      debugPrint('❌ [BACKGROUND_TIMER] Tick error: $e');
    }
  });

  // Clean up on stop
  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });
}
