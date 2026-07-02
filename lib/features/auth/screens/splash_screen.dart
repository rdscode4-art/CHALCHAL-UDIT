import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/active_ride_storage.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/ride.dart';
import '../../../core/widgets/app_logo.dart';
import '../../driver/data/driver_repository.dart';
import '../../driver/screens/driver_home_screen.dart';
import '../../user/screens/user_home_screen.dart';
import '../../user/screens/user_ride_progress_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scale = Tween<double>(
      begin: 0.78,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );
    _ctrl.forward();

    // Start initialization concurrently with animation
    _startApp();
  }

  Future<void> _startApp() async {
    final routeFuture = _determineNextRoute();
    
    // Wait a minimum of 1200ms to show the splash animation
    await Future.delayed(const Duration(milliseconds: 1200));
    
    final nextRoute = await routeFuture;
    
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => nextRoute),
    );
  }

  Future<Widget> _determineNextRoute() async {

    final session = await SessionService.getSession();
    final role = session['role'] ?? '';
    final id = session['id'] ?? '';

    // Check for active ride first (CRITICAL FIX #1: Restore ride after app reopen)
    if (role == 'user' && id.isNotEmpty) {
      try {
        final activeRideRes = await ApiService.getCurrentActiveRide(id);

        if (activeRideRes.success) {
          final rideData = activeRideRes.data;
          final ride = Ride.fromJson(rideData);

          if (ride.id.isNotEmpty) {
            await ActiveRideStorage.save(ride.id);
            final isConfirmedOrStarted = ride.isAccepted || ride.isOngoing;

            if (isConfirmedOrStarted) {
              // Don't navigate to home - go to ride progress instead
              debugPrint(
                'SUCCESS [SPLASH] Active ride found, navigating to UserRideProgressScreen',
              );
              return UserRideProgressScreen(
                rideId: ride.id,
                pickup:
                    rideData['pickup']?.toString() ??
                    rideData['pickupLocation']?.toString() ??
                    'Pickup',
                destination:
                    rideData['destination']?.toString() ??
                    rideData['dropoffLocation']?.toString() ??
                    'Destination',
                rideType: rideData['vehicleType']?.toString() ?? 'Auto',
                ride: ride,
                rideData: rideData,
              );
            } else {
              debugPrint(
                'INFO [SPLASH] Pending/unassigned ride found (status: ${ride.status}), heading to UserHomeScreen',
              );
            }
          }
        } else {
          // No active ride found on server, clear stale local state
          await ActiveRideStorage.clear();
        }
      } catch (e) {
        debugPrint('ERROR [SPLASH] Error restoring ride: $e');
        await ActiveRideStorage.clear();
      }

      // No active ride - proceed to home
      return const UserHomeScreen();
    } else if (role == 'driver' && id.isNotEmpty) {
      // Safety check: call a protected endpoint to verify token validity
      try {
        await ApiService.getDriverDashboard(id);
        
        // If the token was invalid, the global 401 interceptor in ApiService
        // will automatically clear the session and route to WelcomeScreen.
        // We just need to check if the session still exists.
        final currentToken = await SessionService.getToken();
        if (currentToken == null || currentToken.isEmpty) {
          debugPrint('[SPLASH] Session was invalidated during startup check. Aborting DriverHomeScreen navigation.');
          return const OnboardingScreen();
        }
      } catch (e) {
        debugPrint('[SPLASH] Error checking driver session: $e');
      }

      // Restore in-memory driver from saved session so home screen has real data
      DriverRepository.currentDriver = {
        'id': id,
        'name': session['name'] ?? 'Driver',
        'phone': session['phone'] ?? '',
        'vehicleNumber': session['vehicleNumber'] ?? '',
        'vehicleType': session['vehicleType'] ?? 'auto',
        'vehicle': session['vehicleModel'] ?? '',
        'rating': session['rating'] ?? '4.9',
        'experience': session['experience'] ?? '—',
        'status': 'Online',
        'distanceKm': '0.0',
        'eta': '—',
        'license': '',
        'verificationStatus': session['verificationStatus'] ?? 'verified',
        'rejectionReason': session['rejectionReason'] ?? '',
      };
      return const DriverHomeScreen();
    } else {
      // No valid session — clear any stale data and show onboarding
      await SessionService.clear();
      await ActiveRideStorage.clear();
      return const OnboardingScreen();
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChalChalGadiLogo(size: w * 0.64),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: w * 0.28,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          backgroundColor: AppColors.darkBorder,
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.accentYellow,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'My City Ride',
                      style: TextStyle(
                        color: AppColors.accentYellow.withValues(alpha: 0.70),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
