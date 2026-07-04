import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'api_service.dart';
import 'session_service.dart';
import '../utils/device_utils.dart';
import 'shown_rides_storage.dart';

// ─── Notification channel IDs ────────────────────────────────────────────────

// Ride-request channel — plays the custom request_sound.mp3 ringtone.
// Used only for ride_request and ride_assigned notifications.
// NOTE: Channel ID includes a version suffix. Bump the suffix (e.g. _v2 → _v3)
// whenever the sound is changed — Android caches channel settings permanently
// and only picks up the new sound when a brand-new channel ID is registered.
const String _kRideChannelId = 'chalchalgaadi_ride_v2';
const String _kRideChannelName = 'Ride Requests';
const String _kRideChannelDesc = 'Alerts for new ride requests with sound';

// Default channel — uses the system default sound for all other notifications
// (chat messages, admin broadcasts, status updates, etc.)
const String _kHighChannelId = 'chalchalgaadi_high';
const String _kHighChannelName = 'General Alerts';
const String _kHighChannelDesc = 'General app notifications';

// ─── Top-level background handler (must be top-level, not a class method) ────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM-BG] Background message: ${message.messageId}');
  debugPrint('[FCM-BG] Data: ${message.data}');

  final type = message.data['type']?.toString() ?? '';
  final pushTypeBg = message.data['push_type']?.toString() ?? '';
  final eventBg = message.data['event']?.toString() ?? '';
  final rideId = message.data['rideId']?.toString() ?? '';

  // ── Handle Session Terminated ──
  if (type == 'session_terminated' || eventBg == 'logout' || type == 'logout' || type == 'session_ended' || eventBg == 'session_ended') {
    debugPrint('EVENT: session_forced_logout_push');
    debugPrint('[FCM-BG] Session terminated by server. Logging out.');
    await SessionService.clear();
    FlutterBackgroundService().invoke('stopService');
    return;
  }

  // ── Handle Ride Cancelled ──
  final isRideCancelBg = pushTypeBg == 'ride_cancelled' || eventBg == 'cancelled';
  if (isRideCancelBg && rideId.isNotEmpty) {
    debugPrint('[FCM-BG] Ride Cancelled by user. Cancelling notification for $rideId');
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(rideId.hashCode);
    await ShownRidesStorage.addIgnoredRideId(rideId);
    return;
  }

  // ── Skip ride notifications for rides the driver already ignored ──
  final isRideBg =
      type == 'ride_request' ||
      type == 'ride' ||
      pushTypeBg == 'ride' ||
      pushTypeBg == 'ride_request' ||
      eventBg == 'new_request' ||
      eventBg == 'ride_assigned';
  if (isRideBg && rideId.isNotEmpty) {
    final shownIds = await ShownRidesStorage.getShownRideIds();
    final ignoredIds = await ShownRidesStorage.getIgnoredRideIds();
    if (shownIds.contains(rideId) || ignoredIds.contains(rideId)) {
      debugPrint(
        '[FCM-BG] Skipping notification — rideId already shown or ignored: $rideId',
      );
      return;
    }
  }

  await _showLocalNotification(
    id: rideId.isNotEmpty ? rideId.hashCode : message.hashCode,
    title:
        message.notification?.title ??
        message.data['title']?.toString() ??
        'ChalChalGaadi',
    body: message.notification?.body ?? message.data['body']?.toString() ?? '',
    payload: _payloadFromMessage(message),
    isRide:
        type == 'ride_request' ||
        type == 'ride_assigned' ||
        type == 'ride' ||
        message.data['push_type']?.toString() == 'ride' ||
        message.data['event']?.toString() == 'ride_assigned' ||
        message.data['event']?.toString() == 'new_request',
  );
}

/// Build a simple string payload that encodes the navigation intent.
String _payloadFromMessage(RemoteMessage message) {
  final type = message.data['type']?.toString() ?? '';
  final pushType = message.data['push_type']?.toString() ?? '';
  final event = message.data['event']?.toString() ?? '';
  final rideId = message.data['rideId']?.toString() ?? '';

  if (type == 'session_terminated' || event == 'logout' || type == 'logout' || type == 'session_ended' || event == 'session_ended') {
    return 'logout';
  }
  // Treat push_type=ride, type=ride_request/ride_assigned, event=new_request as ride payloads
  final isRide =
      type == 'ride_request' ||
      type == 'ride_assigned' ||
      type == 'ride' ||
      pushType == 'ride' ||
      pushType == 'ride_request' ||
      pushType == 'ride_assigned' ||
      event == 'ride_assigned' ||
      event == 'new_request';
  if (isRide && rideId.isNotEmpty) {
    if (event == 'new_request' || pushType == 'ride_request') {
      return 'new_ride:$rideId';
    }
    return 'ride:$rideId';
  }
  
  if (pushType == 'new_chat_message' && rideId.isNotEmpty) {
    return 'chat:$rideId';
  }

  if (type == 'admin') return 'admin';
  return message.data['payload']?.toString() ?? '';
}

/// Show a local heads-up notification. Safe to call from background isolate
/// because it creates its own plugin instance.
/// [isRide] — true for ride_request / ride_assigned → uses custom sound channel.
Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
  String payload = '',
  bool isRide = false,
}) async {
  if (body.isEmpty && title.isEmpty) return;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  // ── Ride channel (custom sound) ───────────────────────────────────────────
  const customSound = RawResourceAndroidNotificationSound('request_sound');
  const rideChannel = AndroidNotificationChannel(
    _kRideChannelId,
    _kRideChannelName,
    description: _kRideChannelDesc,
    importance: Importance.max,
    playSound: true,
    sound: customSound,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
  // ── Default channel (system sound) ───────────────────────────────────────
  const defaultChannel = AndroidNotificationChannel(
    _kHighChannelId,
    _kHighChannelName,
    description: _kHighChannelDesc,
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  final impl = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await impl?.createNotificationChannel(rideChannel);
  await impl?.createNotificationChannel(defaultChannel);

  final AndroidNotificationDetails androidDetails = isRide
      ? const AndroidNotificationDetails(
          _kRideChannelId,
          _kRideChannelName,
          channelDescription: _kRideChannelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: customSound,
          enableVibration: true,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        )
      : const AndroidNotificationDetails(
          _kHighChannelId,
          _kHighChannelName,
          channelDescription: _kHighChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
        );

  await plugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: payload,
  );
}

// ─── Callback type for navigation after notification tap ─────────────────────
typedef NotificationTapCallback = void Function(String payload);

// ─────────────────────────────────────────────────────────────────────────────
class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();

  factory FirebaseNotificationService() => _instance;
  FirebaseNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Registered once from the root widget so foreground taps can navigate.
  NotificationTapCallback? onNotificationTap;

  /// Called when an FCM foreground message carries push_type == "new_chat_message".
  /// Receives the rideId from the payload. Active chat screens subscribe here
  /// to refresh history without a socket.
  void Function(String rideId)? onNewChatMessage;

  /// Called when a session_terminated or logout event is received.
  void Function()? onSessionTerminated;

  /// Called when a ride_cancelled event is received in the foreground.
  void Function(String rideId)? onRideCancelled;

  /// Called when a user taps a notification for a ride that they have already ignored.
  void Function(String rideId)? onIgnoredRideTap;

  /// Cancel all active system notifications.
  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> initializeNotifications() async {
    // 1. Request Android 13+ permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // 2. Create the high-priority Android notification channel
    await _createAndroidChannel();

    // 3. Initialise flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 4. Background message handler (top-level function)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Foreground messages → show heads-up local notification
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. Background tap (app was in background, user tapped notification)
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 7. Terminated-state launch via notification tap
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] App launched from notification');
      cancelAllNotifications(); // Stop the alarm sound immediately
      // Delay to let the widget tree build before navigating
      Future.delayed(const Duration(milliseconds: 600), () {
        _routeFromPayload(_payloadFromMessage(initialMessage));
      });
    }

    // 8. Log the FCM token
    try {
      final token = await _fcm.getToken();
      if (token != null) debugPrint('[FCM] Token: $token');
    } catch (e) {
      debugPrint('[FCM] Token error: $e');
    }

    // 9. Handle FCM Token Refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM] Token Refreshed: $newToken');
      try {
        final driverId = await SessionService.getDriverId();
        if (driverId != null && driverId.isNotEmpty) {
          final deviceInfo = await DeviceUtils.getDeviceInfo();
          
          // Retry loop for transient network errors
          bool success = false;
          int attempts = 0;
          while (!success && attempts < 2) {
            attempts++;
            final res = await ApiService.updateDriverFcmToken(
              driverId: driverId,
              fcmToken: newToken,
              deviceInfo: deviceInfo,
            );
            
            if (res.success) {
              debugPrint('EVENT: fcm_token_refresh_update_success');
              success = true;
            } else {
              debugPrint('EVENT: fcm_token_refresh_update_failed (attempt $attempts)');
              // If it's explicitly an auth failure, trigger global session clear immediately
              if (res.errorMessage != null && (res.errorMessage!.contains('session') || res.errorMessage!.contains('invalid'))) {
                debugPrint('EVENT: session_forced_logout_401');
                onSessionTerminated?.call();
                break;
              }
              // Wait before retry
              if (attempts < 2) {
                await Future.delayed(const Duration(seconds: 2));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[FCM] Error updating refreshed token: $e');
      }
    });
  }

  // ── Android notification channel ───────────────────────────────────────────

  Future<void> _createAndroidChannel() async {
    // Ride channel — custom sound
    const customSound = RawResourceAndroidNotificationSound('request_sound');
    const rideChannel = AndroidNotificationChannel(
      _kRideChannelId,
      _kRideChannelName,
      description: _kRideChannelDesc,
      importance: Importance.max,
      playSound: true,
      sound: customSound,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    // Default channel — system sound
    const defaultChannel = AndroidNotificationChannel(
      _kHighChannelId,
      _kHighChannelName,
      description: _kHighChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    final impl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await impl?.createNotificationChannel(rideChannel);
    await impl?.createNotificationChannel(defaultChannel);
    debugPrint('[FCM] Android notification channels created');
  }

  // ── Foreground message handler ─────────────────────────────────────────────

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM-FG] Foreground message: ${message.notification?.title}');
    debugPrint('[FCM-FG] Data: ${message.data}');

    final msgType = message.data['type']?.toString() ?? '';
    final msgPushType = message.data['push_type']?.toString() ?? '';
    final msgEventFg = message.data['event']?.toString() ?? '';

    // ── Handle Session Terminated ──
    if (msgType == 'session_terminated' || msgEventFg == 'logout' || msgType == 'logout' || msgType == 'session_ended' || msgEventFg == 'session_ended') {
      debugPrint('EVENT: session_forced_logout_push');
      debugPrint('[FCM-FG] Session terminated by server. Triggering callback.');
      onSessionTerminated?.call();
      return;
    }

    // ── Handle Ride Cancelled ──
    final msgRideId = message.data['rideId']?.toString() ?? '';
    if (msgPushType == 'ride_cancelled' || msgEventFg == 'cancelled') {
      if (msgRideId.isNotEmpty) {
        debugPrint('[FCM-FG] Ride cancelled by user (rideId=$msgRideId). Triggering callback.');
        onRideCancelled?.call(msgRideId);
      }
      return; // Do NOT show a heads-up notification
    }

    // ── Silent chat refresh ───────────────────────────────────────────────────────
    // new_chat_message is a data-only push — don't show a system notification,
    // just notify the open chat screen to re-fetch history.
    if (msgPushType == 'new_chat_message') {
      final rideId = message.data['rideId']?.toString() ?? '';
      debugPrint('[FCM-FG] new_chat_message for rideId=$rideId');
      onNewChatMessage?.call(rideId);
      return; // Do NOT show a heads-up notification for chat messages
    }

    // ── Skip ride notifications for rides the driver already ignored ──
    final isRidePush =
        msgType == 'ride_request' ||
        msgType == 'ride' ||
        msgPushType == 'ride' ||
        msgPushType == 'ride_request' ||
        msgEventFg == 'new_request';
    if (isRidePush && msgRideId.isNotEmpty) {
      // The DriverHomeScreen handles 'new_request' and 'ride_assigned' with custom 
      // full-screen UI and sounds. We must suppress the system banner notification 
      // here to prevent duplicate sounds and redundant popups.
      debugPrint('[FCM-FG] Suppressing banner notification for ride push to let DriverHomeScreen handle it natively.');
      return;
    }

    _showForegroundNotification(message);
  }

  void _showForegroundNotification(RemoteMessage message) {
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'ChalChalGaadi';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';

    if (body.isEmpty && title == 'ChalChalGaadi') return; // skip empty messages

    final msgType = message.data['type']?.toString() ?? '';
    final msgEvent = message.data['event']?.toString() ?? '';
    final msgPushType = message.data['push_type']?.toString() ?? '';
    final isRide =
        msgType == 'ride_request' ||
        msgType == 'ride_assigned' ||
        msgType == 'ride' ||
        msgPushType == 'ride' ||
        msgPushType == 'ride_request' ||
        msgPushType == 'ride_assigned' ||
        msgEvent == 'ride_assigned' ||
        msgEvent == 'new_request';

    // Show a heads-up notification so the driver/user sees it even in foreground
    final msgRideId = message.data['rideId']?.toString() ?? '';
    _showLocalNotification(
      id: msgRideId.isNotEmpty ? msgRideId.hashCode : message.hashCode,
      title: title,
      body: body,
      payload: _payloadFromMessage(message),
      isRide: isRide,
    );
  }

  // ── Notification tap handlers ────────────────────────────────────────────────

  /// Called when user taps a local notification (flutter_local_notifications).
  void _onLocalNotificationTap(NotificationResponse response) {
    debugPrint('[FCM] Local notification tapped: ${response.payload}');
    cancelAllNotifications();
    _routeFromPayload(response.payload ?? '');
  }

  /// Called when user taps an FCM notification from background state.
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification opened app: ${message.data}');
    cancelAllNotifications();
    _routeFromPayload(_payloadFromMessage(message));
  }

  /// Dispatch navigation based on payload string.
  /// For ride requests, silently skip if the driver already ignored that ride.
  void _routeFromPayload(String payload) {
    if (payload.isEmpty) return;
    debugPrint('[FCM] Routing from payload: $payload');

    // If this is a ride notification, check if the driver ignored it already.
    if (payload.startsWith('ride:') || payload.startsWith('new_ride:')) {
      final isNewRide = payload.startsWith('new_ride:');
      final prefixLen = isNewRide ? 9 : 5;
      final rideId = payload.substring(prefixLen).trim();
      if (rideId.isNotEmpty) {
        ShownRidesStorage.getShownRideIds().then((ignoredIds) {
          if (ignoredIds.contains(rideId)) {
            debugPrint(
              '[FCM] Ignoring tapped notification — rideId already dismissed: $rideId',
            );
            onIgnoredRideTap?.call(rideId);
            return; // Don’t navigate — driver already declined this ride
          }
          onNotificationTap?.call(payload);
        });
        return;
      }
    }

    onNotificationTap?.call(payload);
  }

  // ── Public helpers ─────────────────────────────────────────────────────────

  /// Checks if a specific rideId has been marked as ignored.
  Future<bool> isRideIgnored(String rideId) async {
    final ignoredIds = await ShownRidesStorage.getShownRideIds();
    return ignoredIds.contains(rideId);
  }

  /// Show a local notification directly (e.g. from admin broadcast).
  Future<void> showAdminNotification({
    required String title,
    required String body,
  }) async {
    await _showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: 'admin',
    );
  }

  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }

  Future<void> uploadFcmTokenToBackend({
    required String userId,
    required String role, // 'user' or 'driver'
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FCM] No token to upload');
        return;
      }
      debugPrint('[FCM] Uploading token for $role: $userId');
      if (role == 'user') {
        final res = await ApiService.updateUserFcmToken(
          userId: userId,
          fcmToken: token,
        );
        debugPrint(
          res.success
              ? '[FCM] User token uploaded'
              : '[FCM] User token upload failed: ${res.errorMessage}',
        );
      } else if (role == 'driver') {
        final res = await ApiService.updateDriverFcmToken(
          driverId: userId,
          fcmToken: token,
        );
        debugPrint(
          res.success
              ? '[FCM] Driver token uploaded'
              : '[FCM] Driver token upload failed: ${res.errorMessage}',
        );
      }
    } catch (e) {
      debugPrint('[FCM] uploadFcmTokenToBackend error: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      debugPrint('[FCM] Subscribed to: $topic');
    } catch (e) {
      debugPrint('[FCM] subscribeToTopic error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      debugPrint('[FCM] Unsubscribed from: $topic');
    } catch (e) {
      debugPrint('[FCM] unsubscribeFromTopic error: $e');
    }
  }
}
