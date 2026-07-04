import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'firebase_options.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_theme.dart';
import 'core/services/app_route_observer.dart';
import 'core/services/firebase_notification_service.dart';
import 'core/localization/app_localizations.dart';
import 'core/services/background_service.dart';
import 'core/widgets/chat_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'core/services/session_service.dart';
import 'core/services/api_service.dart';

import 'features/driver/screens/driver_bubble_overlay.dart';

/// Global navigator key — lets the FCM tap callback navigate from outside
/// the widget tree (background / terminated notification taps).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DriverBubbleOverlay(),
    ),
  );
}

/// Reactive notifier for pending ride actions from notifications.
/// Consumed by DriverHomeScreen to show popups.
final ValueNotifier<String?> globalPendingRideAction = ValueNotifier<String?>(null);

/// Legacy getter for compatibility, though reactive listening is preferred.
String? consumePendingRideId() {
  final id = globalPendingRideAction.value;
  globalPendingRideAction.value = null;
  return id;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (!kIsWeb) {
    await initializeBackgroundService();
  }
  await LanguageManager.init();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
  }

  // Register the notification tap callback BEFORE initialising so that
  // terminated-state launches are routed correctly.
  FirebaseNotificationService().onNotificationTap = (payload) async {
    debugPrint('[FCM] Notification tap payload: $payload');

    // Check if it's a chat notification
    if (payload.startsWith('chat:')) {
      final rideId = payload.substring(5).trim();
      if (rideId.isNotEmpty) {
        final driverId = await SessionService.getDriverId();
        final userId = await SessionService.getUserId();

        final senderModel = (driverId != null && driverId.isNotEmpty)
            ? 'driver'
            : 'user';
        final senderId = (senderModel == 'driver') ? driverId : userId;
        final otherPartyName = (senderModel == 'driver')
            ? 'Customer'
            : 'Driver';

        if (senderId != null && senderId.isNotEmpty) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                rideId: rideId,
                senderId: senderId,
                senderModel: senderModel,
                otherPartyName: otherPartyName,
              ),
            ),
          );
        }
      }
      return;
    }

    // If it's a ride payload, store the rideId so DriverHomeScreen
    // can show the popup immediately without waiting for the next poll
    if (payload.startsWith('ride:') || payload.startsWith('new_ride:')) {
      final isNewRide = payload.startsWith('new_ride:');
      if (!isNewRide) {
        // Pop to root (home screen) immediately for assigned rides
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
      final prefixLen = isNewRide ? 9 : 5;
      final rideId = payload.substring(prefixLen).trim();
      if (rideId.isNotEmpty) {
        globalPendingRideAction.value = payload; // Reactive notification payload
      }
    } else {
      // Pop to root (home screen) immediately for other notifications
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
  };

  void handleGlobalLogout(String reason) async {
    debugPrint('[SESSION] Global logout triggered. Reason: $reason');
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Session Expired'),
          content: const Text(
            'You have been logged out because your account was accessed from another device.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (r) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    await SessionService.clear();
    if (!kIsWeb) {
      FlutterBackgroundService().invoke('stopService');
    }
  }

  FirebaseNotificationService().onSessionTerminated = () {
    handleGlobalLogout('FCM Push Notification');
  };

  ApiService.onSessionExpired = () {
    handleGlobalLogout('API 401 Unauthorized');
  };

  if (!kIsWeb) {
    try {
      await FirebaseNotificationService().initializeNotifications();
      debugPrint('✅ Firebase Notifications initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Firebase Notifications initialization failed: $e');
    }
  }

  runApp(const RideGoApp());
}

class RideGoApp extends StatefulWidget {
  const RideGoApp({super.key});

  @override
  State<RideGoApp> createState() => _RideGoAppState();
}

class _RideGoAppState extends State<RideGoApp> {
  @override
  Widget build(BuildContext context) {
    // ── Light theme ──────────────────────────────────────────────────────────
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accentStrong,
        onSecondary: Colors.white,
        error: AppColors.accentRed,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textDark,
        tertiary: AppColors.accentYellow,
        onTertiary: AppColors.textDark,
      ),
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppColors.surface,
        elevation: 0,
        shadowColor: AppColors.textDark.withValues(alpha: 0.08),
        iconTheme: const IconThemeData(color: AppColors.textDark),
        titleTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.textDark,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      iconTheme: const IconThemeData(color: AppColors.textDark),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: AppColors.textDark,
        displayColor: AppColors.textDark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSoft,
        hintStyle: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentStrong, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentStrong,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentStrong,
          side: const BorderSide(color: AppColors.accentStrong, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentStrong
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentStrong.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSoft,
        labelStyle: GoogleFonts.inter(color: AppColors.textDark, fontSize: 12),
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primary,
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentStrong,
        linearTrackColor: AppColors.surfaceSoft,
      ),
    );

    // ── Dark theme ───────────────────────────────────────────────────────────
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkBackground,
        secondary: AppColors.accentStrong,
        onSecondary: Colors.white,
        error: AppColors.accentRed,
        onError: Colors.white,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkOnSurface,
        tertiary: AppColors.accentYellow,
        onTertiary: AppColors.textDark,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkSurface,
      canvasColor: AppColors.darkBackground,
      dividerColor: AppColors.darkBorder,
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppColors.darkSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.darkOnSurface),
        titleTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.darkOnSurface,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      iconTheme: const IconThemeData(color: AppColors.darkOnSurface),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: AppColors.darkOnSurface,
        displayColor: AppColors.darkOnSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceSoft,
        hintStyle: TextStyle(
          color: AppColors.darkOnSurface.withValues(alpha: 0.45),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentYellow, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentStrong,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentYellow,
          side: const BorderSide(color: AppColors.accentYellow, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentStrong
              : AppColors.darkBorder,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentStrong.withValues(alpha: 0.4)
              : AppColors.darkSurfaceVariant,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurfaceSoft,
        labelStyle: GoogleFonts.inter(
          color: AppColors.darkOnSurface,
          fontSize: 12,
        ),
        side: BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceSoft,
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.darkBorder),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.darkSurface,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.darkSurface,
        iconColor: AppColors.darkOnSurface,
        textColor: AppColors.darkOnSurface,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.accentStrong,
        unselectedItemColor: AppColors.darkOnSurface.withValues(alpha: 0.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentStrong,
        linearTrackColor: AppColors.darkSurfaceSoft,
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: LanguageManager.localeNotifier,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'Chal Chal Gadi',
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('hi')],
              themeAnimationDuration: const Duration(milliseconds: 400),
              themeAnimationCurve: Curves.easeInOut,
              navigatorObservers: [appRouteObserver],
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
