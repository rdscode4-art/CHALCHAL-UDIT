import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ridego/core/services/map_utils.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/home_banner_carousel.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../auth/screens/welcome_screen.dart';
import '../../../core/services/active_ride_storage.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_route_observer.dart';
import '../../../services/category_service.dart';
import '../../../core/models/ride.dart';
import 'map_location_picker_screen.dart';
import 'select_ride_screen.dart';
import 'user_profile_screen.dart';
import 'drivers_list_screen.dart';
import 'ride_confirmation_screen.dart';
import 'user_ride_progress_screen.dart';
import '../../../core/localization/app_localizations.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> with RouteAware {
  final _pickupCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _destFocusNode = FocusNode();
  String _selectedVehicleType = 'Auto';
  int _bottomNavIndex = 0;
  String _userName = '';
  bool _loadingRides = false;
  String? _ridesError;

  Timer? _debounceTimer;
  Timer? _currentRideTimer;
  final bool _navigatedToActiveRide = false;
  Timer? _pendingRideTimer;
  Ride? _pendingRide;

  final List<String> _localLocationFallback = [
    'H No. 21, Silver Street, Sector 7',
    'Office Tower, City Center',
    'Airport Terminal, North Gate',
    'Station Square, Central Mall',
    'Mall Road, Block B',
    'Tech Park, Business District',
    'Greenview Apartments',
    'Sunrise Mall, East Wing',
  ];

  List<Map<String, String>> _filteredSuggestions = [];
  List<Map<String, String>> _pickupSuggestions = [];
  bool _showDestinationSuggestions = false;
  bool _showPickupSuggestions = false;

  List<Map<String, dynamic>> _vehicleTypes = [];
  bool _loadingCategories = true; // true until first API response arrives
  // ignore: unused_field
  List<Map<String, dynamic>> _serviceOptions = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _featureOptions = [];
  List<Map<String, dynamic>> _bottomNavItems = [
    {'icon': Icons.home_rounded, 'label': 'Home'},
    {'icon': Icons.receipt_long_rounded, 'label': 'My Rides'},
    {'icon': Icons.person_rounded, 'label': 'Profile'},
  ];
  List<Map<String, dynamic>> _quickTags = [];

  final List<Map<String, dynamic>> _savedPlaces = [];

  final List<Map<String, dynamic>> _recentLocations = [];

  List<Map<String, dynamic>> _rideHistoryRecords = [];

  String _historySearchQuery = '';
  String _historySelectedRideType = 'All';
  String _historySelectedDateOption = 'All Time';
  DateTimeRange? _historyCustomDateRange;
  String _historySelectedFareOption = 'All';
  String _historySortBy = 'Newest';
  final TextEditingController _historySearchController =
      TextEditingController();

  final LatLng _initialCenter = LatLng(28.6139, 77.2090);
  GoogleMapController? _mapController;
  // Home map dynamic state
  LatLng _mapCenter = LatLng(28.6139, 77.2090);
  LatLng? _pickupPoint;
  LatLng? _destinationPoint;
  List<LatLng> _homeRoutePoints = [];
  Set<Marker> _homeMarkers = {};
  Timer? _nearbyDriversTimer;
  List<Map<String, dynamic>> _nearbyDrivers = [];
  final Map<String, BitmapDescriptor> _emojiMarkerCache = {};
  String? _lastGeocodedPickupText;
  String? _lastGeocodedDestText;
  // Tracks text set by a suggestion selection — suppresses re-fetch on that value
  String? _pickupSelectedText;
  String? _destSelectedText;

  bool get _supportsMap {
    final key = AppConstants.googlePlacesApiKey;
    final validKey = key.isNotEmpty && !key.startsWith('YOUR_');
    return validKey &&
        (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  Widget _buildSavedPlace(Map<String, dynamic> place) {
    return GestureDetector(
      onTap: () => _selectDestinationItem(place['address'] as String),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),

        margin: const EdgeInsets.only(bottom: 14),

        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),

          border: Border.all(color: AppColors.border),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ICON
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentStrong.withValues(alpha: 0.10),

                borderRadius: BorderRadius.circular(16),
              ),

              child: Icon(
                place['icon'] as IconData,
                color: AppColors.accentStrong,
                size: 24,
              ),
            ),

            const SizedBox(width: 14),

            /// CONTENT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place['label'] as String,

                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,

                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),

                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withValues(alpha: 0.12),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Text(
                          'Saved',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentYellow,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    place['address'] as String,

                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,

                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: AppColors.textGrey,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        'Quick access',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 11,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            /// ACTION BUTTON
            GestureDetector(
              onTap: () {
                setState(() {
                  _savedPlaces.remove(place);
                });
                _deletePlaceFromBackend(place);

                _showInfo('Removed from saved places');
              },

              child: Container(
                padding: const EdgeInsets.all(8),

                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLocation(Map<String, dynamic> location) {
    final bool alreadySaved = _savedPlaces.any(
      (item) => item['address'] == location['address'],
    );

    return GestureDetector(
      onTap: () => _selectDestinationItem(location['address'] as String),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),

        margin: const EdgeInsets.only(bottom: 12),

        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(color: AppColors.border),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HISTORY ICON
            Container(
              padding: const EdgeInsets.all(10),

              decoration: BoxDecoration(
                color: AppColors.accentStrong.withValues(alpha: 0.10),

                borderRadius: BorderRadius.circular(14),
              ),

              child: const Icon(
                Icons.history,
                color: AppColors.accentStrong,
                size: 22,
              ),
            ),

            const SizedBox(width: 14),

            /// TEXT CONTENT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          location['label'] as String,

                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,

                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Text(
                        'Recent',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentStrong,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    location['address'] as String,

                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,

                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Icon(Icons.replay, size: 14, color: AppColors.textGrey),

                      const SizedBox(width: 6),

                      Text(
                        'Tap to reuse',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 11,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            /// SAVE BUTTON
            GestureDetector(
              onTap: () {
                if (alreadySaved) return;
                setState(() {
                  _addToSavedPlaces(location);
                });
                _showInfo('Saved to your places');
              },
              child: Container(
                padding: const EdgeInsets.all(8),

                decoration: BoxDecoration(
                  color: alreadySaved
                      ? AppColors.accentYellow.withValues(alpha: 0.15)
                      : AppColors.accentStrong.withValues(alpha: 0.10),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(
                  alreadySaved ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                  color: alreadySaved
                      ? AppColors.accentYellow
                      : AppColors.accentStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _proceedToSelectRide() async {
    if (_pendingRide != null) {
      _showInfo(
        'You already have a pending or active ride. Please complete or cancel it before booking a new one.',
      );
      return;
    }

    final pickup = _pickupCtrl.text.trim();
    final destination = _destCtrl.text.trim();
    if (pickup.isEmpty) {
      _showInfo(context.tr('enterPickupErr'));
      return;
    }
    if (destination.isEmpty) {
      _showInfo(context.tr('enterDestErr'));
      return;
    }

    final navigator = Navigator.of(context);
    final resolvedPickup = await _resolveAddress(pickup);
    final resolvedDestination = await _resolveAddress(destination);
    if (!mounted) return;
    _selectPickupLocation(resolvedPickup);
    _selectDestinationItem(resolvedDestination);

    navigator.push(
      MaterialPageRoute(
        builder: (_) => SelectRideScreen(
          pickup: resolvedPickup,
          destination: resolvedDestination,
          vehicleType: _selectedVehicleType,
          pickupLatLng: _pickupPoint,
          destinationLatLng: _destinationPoint,
        ),
      ),
    );
  }

  Widget _buildRideCategoryCard(Map<String, dynamic> category) {
    final bool selected = category['name'] == _selectedVehicleType;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicleType = category['name'] as String;
        });
        
        // Auto-proceed if both locations are entered
        if (_pickupCtrl.text.trim().isNotEmpty && _destCtrl.text.trim().isNotEmpty) {
          _proceedToSelectRide();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentStrong : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accentStrong : AppColors.border,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.accentStrong.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// ICON / CATEGORY IMAGE
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.accentStrong.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CategoryVehicleImage(
                  vehicleType:
                      category['key']?.toString() ??
                      category['name']?.toString() ??
                      '',
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 8),

            /// TITLE
            Text(
              category['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton card shown while categories are loading from the API.
  Widget _buildCategoryShimmer() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRideBanner(Ride ride) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark
        ? AppColors.darkOnSurface
        : AppColors.textDark;
    final cardBg = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.9);

    final rideData = ride.raw;
    final pickupStr =
        rideData['pickup']?.toString() ??
        rideData['pickupLocation']?.toString() ??
        'Pickup';
    final destStr =
        rideData['destination']?.toString() ??
        rideData['dropoffLocation']?.toString() ??
        'Destination';
    final statusStr = ride.status.toLowerCase();

    // Map status to localized / readable string
    String readableStatus = 'Looking for drivers...';
    if (statusStr == 'assigned') {
      readableStatus = 'Waiting for driver to accept...';
    } else if (statusStr == 'accepted') {
      readableStatus = 'Driver accepted, arriving soon';
    } else if (statusStr == 'ongoing' || statusStr == 'started') {
      readableStatus = 'Ongoing trip';
    }

    return Container(
      width: double.infinity,
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
                  Icons.directions_car_filled_rounded,
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
                      context.tr('activeBookingInProgress'),
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
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Cancel Ride?'),
                        content: const Text(
                          'Are you sure you want to cancel this pending ride?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('No'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Yes, Cancel'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      setState(() {
                        _pendingRide = null;
                      });
                      await ApiService.cancelRide(rideId: ride.id);
                      await ActiveRideStorage.clear();
                      _showInfo('Ride cancelled successfully');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentRed,
                    side: const BorderSide(
                      color: AppColors.accentRed,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    context.tr('cancelRideBtn'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _resumePendingRide(ride),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentStrong,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    context.tr('resumeRide'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDynamicOptions();
    _loadUserName();
    // Fetch & cache category images for the user role after build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CategoryService.instance.fetchCategories(role: 'user');
    });
    _fetchUserRides();
    _fetchSavedPlaces();
    _fetchRecentLocations();
    _startCurrentRidePolling();
    _pickupCtrl.addListener(_updatePickupSuggestions);
    _destCtrl.addListener(_updateDestinationSuggestions);
    _pickupFocusNode.addListener(_updateSearchFocus);
    _destFocusNode.addListener(_updateSearchFocus);
    _initializeCurrentLocation();
    _startNearbyDriversPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // When coming back to home screen from a pushed route, refresh ride history
    // and clear any leftover destination so the user starts fresh.
    _fetchUserRides();
    _clearDestinationOnReturn();
    _checkPendingRide();
    // Refresh the pickup location to user's actual live GPS location
    _initializeCurrentLocation();
  }

  /// Clears the destination field and resets map state when returning to home.
  void _clearDestinationOnReturn() {
    if (!mounted) return;
    setState(() {
      _destCtrl.clear();
      _destinationPoint = null;
      _lastGeocodedDestText = null;
      _homeRoutePoints = [];
    });
    // Rebuild map markers without the destination pin
    _updateHomeMap();
  }

  Future<void> _initializeCurrentLocation() async {
    try {
      final locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        final permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return;
        }
      }

      // Check last known position for instant feedback
      final lastKnown = await Geolocator.getLastKnownPosition();
      LatLng? fallbackLatLng;
      if (lastKnown != null && mounted) {
        fallbackLatLng = LatLng(lastKnown.latitude, lastKnown.longitude);
        setState(() {
          _mapCenter = fallbackLatLng!;
          _pickupPoint = fallbackLatLng;
        });
        if (_mapController != null) {
          _mapController!.moveCamera(
            CameraUpdate.newLatLngZoom(fallbackLatLng, 15),
          );
        }
        _fetchNearbyDrivers();

        // Optimistically reverse geocode
        final addr = await _fetchAddressFromCoordinates(fallbackLatLng);
        if (mounted && addr != null) {
          setState(() {
            _pickupCtrl.text = addr;
            _lastGeocodedPickupText = addr.trim();
          });
        }
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        ).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('Geolocator.getCurrentPosition failed or timed out: $e');
      }

      final currentLatLng = position != null
          ? LatLng(position.latitude, position.longitude)
          : fallbackLatLng;

      if (currentLatLng != null) {
        _mapCenter = currentLatLng;
        _pickupPoint = currentLatLng;

        // Reverse geocode to get readable address
        final address =
            await _fetchAddressFromCoordinates(currentLatLng) ??
            'Your Current Location';

        if (mounted) {
          setState(() {
            _pickupCtrl.text = address;
            _lastGeocodedPickupText = address.trim();
            _mapCenter = currentLatLng;
            _pickupPoint = currentLatLng;
          });
          // Fetch nearby drivers immediately for the resolved current position
          _fetchNearbyDrivers();
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize current location: $e');
    }
  }

  void _startCurrentRidePolling() async {
    // Check once immediately on load
    _checkPendingRide();

    // Check periodically every 5 seconds
    _pendingRideTimer?.cancel();
    _pendingRideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkPendingRide();
    });
  }

  Future<void> _checkPendingRide() async {
    try {
      final userId = await SessionService.getUserId();
      if (userId == null || userId.isEmpty) return;

      final res = await ApiService.getCurrentActiveRide(userId);
      if (!mounted) return;

      if (res.success) {
        final ride = Ride.fromJson(res.data);
        if (ride.id.isNotEmpty) {
          await ActiveRideStorage.save(ride.id);
          setState(() {
            _pendingRide = ride;
          });
        }
      } else {
        // No active ride found on server, clear local state
        await ActiveRideStorage.clear();
        if (mounted) {
          setState(() {
            _pendingRide = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking pending ride: $e');
    }
  }

  void _resumePendingRide(Ride ride) {
    final rideData = ride.raw;
    final status = ride.status.toLowerCase();

    final pickupStr =
        rideData['pickup']?.toString() ??
        rideData['pickupLocation']?.toString() ??
        'Pickup';
    final destStr =
        rideData['destination']?.toString() ??
        rideData['dropoffLocation']?.toString() ??
        'Destination';
    final vehicleTypeStr =
        rideData['vehicleType']?.toString() ??
        rideData['rideType']?.toString() ??
        'Auto';

    final double? distKm =
        (rideData['distanceKm'] as num?)?.toDouble() ??
        double.tryParse(rideData['distance']?.toString() ?? '');
    final double? durMin =
        (rideData['durationMin'] as num?)?.toDouble() ??
        double.tryParse(rideData['duration']?.toString() ?? '');

    if (status == 'pending') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DriversListScreen(
            rideType: vehicleTypeStr,
            pickup: pickupStr,
            destination: destStr,
            rideId: ride.id,
            pickupLat: ride.pickupLat ?? 28.6139,
            pickupLng: ride.pickupLng ?? 77.2090,
            distanceKm: distKm,
            durationMin: durMin,
          ),
        ),
      );
    } else if (status == 'assigned') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RideConfirmationScreen(
            rideId: ride.id,
            rideType: vehicleTypeStr,
            pickup: pickupStr,
            destination: destStr,
            driver: ride.driver,
            fare: ride.fare?.toString(),
            distanceKm: distKm,
            durationMin: durMin,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserRideProgressScreen(
            rideId: ride.id,
            pickup: pickupStr,
            destination: destStr,
            rideType: vehicleTypeStr,
            ride: ride,
            rideData: rideData,
          ),
        ),
      );
    }
  }

  Future<void> _loadUserName() async {
    final session = await SessionService.getSession();
    final name = session['name'] ?? '';
    if (mounted && name.isNotEmpty) {
      setState(() => _userName = name);
    }
  }

  Future<void> _fetchUserRides() async {
    final userId = await SessionService.getUserId();
    if (userId == null || userId.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loadingRides = true;
      _ridesError = null;
    });

    final res = await ApiService.getUserRides(userId);
    if (!mounted) return;

    if (res.success) {
      final List<dynamic> ridesList = res.data['rides'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> parsedRides = [];
      for (var item in ridesList) {
        if (item is Map<String, dynamic>) {
          final pickup =
              item['pickup']?.toString() ??
              item['pickupLocation']?.toString() ??
              'Pickup';
          final dest =
              item['destination']?.toString() ??
              item['dropoffLocation']?.toString() ??
              'Destination';

          // Fare: prioritise finalFare (set on completion) then fall back
          var fareStr = '—';
          final rawFare =
              item['finalFare'] ??
              item['fare'] ??
              item['price'] ??
              item['estimatedFare'];
          if (rawFare != null) {
            final rawFareStr = rawFare.toString().trim();
            final numericOnly = rawFareStr.replaceAll(RegExp(r'[^0-9.]'), '');
            if (numericOnly.isNotEmpty && numericOnly != '0') {
              fareStr = '₹$numericOnly';
            }
          }

          var dateStr = '—';
          var timeStr = '—';
          // Keep raw ISO timestamp so sorting/filtering always works
          final rawDateIso =
              item['completedAt']?.toString() ??
              item['startedAt']?.toString() ??
              item['createdAt']?.toString() ??
              item['date']?.toString();
          if (rawDateIso != null && rawDateIso.isNotEmpty) {
            try {
              final parsedDate = DateTime.parse(rawDateIso).toLocal();
              dateStr = _formatDate(parsedDate);
              timeStr = _formatTime(parsedDate);
            } catch (_) {
              dateStr = rawDateIso;
            }
          }

          final driverMap = (item['driverDetails'] is Map<String, dynamic>)
              ? item['driverDetails'] as Map<String, dynamic>
              : (item['driver'] is Map<String, dynamic>)
              ? item['driver'] as Map<String, dynamic>
              : (item['driverId'] is Map<String, dynamic>)
              ? item['driverId'] as Map<String, dynamic>
              : (item['assignedDriverId'] is Map<String, dynamic>)
              ? item['assignedDriverId'] as Map<String, dynamic>
              : null;

          var driverName = driverMap?['name']?.toString() ?? 'Driver';
          if (driverName == 'Driver') {
            driverName = item['driverName']?.toString() ?? 'Driver';
          }
          var driverPhone = driverMap?['phone']?.toString() ?? '—';
          if (driverPhone == '—') {
            driverPhone = item['driverPhone']?.toString() ?? '—';
          }
          var driverVehicle =
              driverMap?['vehicleNumber']?.toString() ??
              driverMap?['vehicle']?.toString() ??
              '—';
          if (driverVehicle == '—') {
            driverVehicle =
                item['vehicleNumber']?.toString() ??
                item['vehicle']?.toString() ??
                '—';
          }
          var driverType =
              driverMap?['vehicleType']?.toString() ??
              driverMap?['rideType']?.toString() ??
              '—';
          if (driverType == '—') {
            driverType =
                item['vehicleType']?.toString() ??
                item['rideType']?.toString() ??
                '—';
          }

          final rating =
              item['rating'] ??
              double.tryParse(driverMap?['rating']?.toString() ?? '4.9') ??
              4.9;

          var distanceStr = '—';
          final rawDistance =
              item['distance'] ?? item['distanceKm'] ?? item['distance_km'];
          if (rawDistance != null) {
            distanceStr = rawDistance.toString();
            if (!distanceStr.toLowerCase().contains('km') &&
                double.tryParse(distanceStr) != null) {
              distanceStr = '$distanceStr km';
            }
          }

          var durationStr = '—';
          final rawDuration =
              item['duration'] ??
              item['durationMin'] ??
              item['duration_min'] ??
              item['durationMins'];
          if (rawDuration != null) {
            durationStr = rawDuration.toString();
            if (!durationStr.toLowerCase().contains('min') &&
                int.tryParse(durationStr) != null) {
              durationStr = '$durationStr mins';
            }
          }

          final uId = item['userId'] is Map
              ? (item['userId']['_id'] ?? item['userId']['id'])?.toString() ??
                    ''
              : item['userId']?.toString() ?? '';
          final dId =
              driverMap?['_id']?.toString() ??
              driverMap?['id']?.toString() ??
              item['driverId']?.toString() ??
              item['assignedDriverId']?.toString() ??
              '';
          final rId = item['_id']?.toString() ?? item['id']?.toString() ?? '';

          final rideStatus = (item['status']?.toString() ?? '').toLowerCase();
          // Only show completed rides in history
          final isCompleted =
              rideStatus == 'completed' ||
              rideStatus == 'ended' ||
              rideStatus == 'complete' ||
              rideStatus == 'done' ||
              rideStatus == 'finished';
          if (isCompleted) {
            parsedRides.add({
              'date': dateStr,
              'time': timeStr,
              'createdAt': rawDateIso ?? '',
              'pickup': pickup,
              'dropoff': dest,
              'fare': fareStr,
              'rating': rating,
              'driver': driverName,
              'driverPhone': driverPhone,
              'vehicleNumber': driverVehicle,
              'vehicleType': driverType,
              'distance': distanceStr,
              'duration': durationStr,
              'rideId': rId,
              'rideStatus': 'completed',
              'userId': uId,
              'driverId': dId,
            });
          }
        }
      }
      setState(() {
        _rideHistoryRecords.clear();
        _rideHistoryRecords.addAll(parsedRides);
        _loadingRides = false;
      });
      // Enrich each ride with real fare/distance/rating from individual ride API
      _enrichUserRidesFromIds(parsedRides);
    } else {
      setState(() {
        _loadingRides = false;
        _ridesError = res.errorMessage;
      });
    }
  }

  Future<void> _fetchSavedPlaces() async {
    final userId = await SessionService.getUserId();
    if (userId == null || userId.isEmpty) return;

    final res = await ApiService.getSavedPlaces(userId);
    if (!mounted) return;

    if (res.success) {
      final List<dynamic> placesList =
          res.data['savedPlaces'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> parsedPlaces = [];
      for (var item in placesList) {
        if (item is Map<String, dynamic>) {
          final String name = item['name']?.toString() ?? 'Saved Place';
          final String address = item['address']?.toString() ?? '';
          final String type = item['type']?.toString() ?? 'other';

          IconData icon = Icons.location_on;
          if (type.toLowerCase() == 'home') {
            icon = Icons.home;
          } else if (type.toLowerCase() == 'work') {
            icon = Icons.work;
          }

          final String id =
              item['id']?.toString() ?? item['_id']?.toString() ?? '';
          parsedPlaces.add({
            'id': id,
            'label': name,
            'address': address,
            'icon': icon,
            'lat': item['lat'],
            'lng': item['lng'],
            'type': type,
          });
        }
      }

      setState(() {
        _savedPlaces.clear();
        _savedPlaces.addAll(parsedPlaces);
      });
    }
  }

  Future<void> _fetchRecentLocations() async {
    final userId = await SessionService.getUserId();
    if (userId == null || userId.isEmpty) return;

    final res = await ApiService.getRecentLocations(userId);
    if (!mounted) return;

    if (res.success) {
      final List<dynamic> locationsList =
          res.data['recentLocations'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> parsedLocations = [];
      for (var item in locationsList) {
        if (item is Map<String, dynamic>) {
          final String name = item['name']?.toString() ?? 'Recent Place';
          final String address = item['address']?.toString() ?? '';

          parsedLocations.add({
            'label': name,
            'address': address,
            'icon': Icons.history,
            'lat': item['lat'],
            'lng': item['lng'],
          });
        }
      }

      setState(() {
        _recentLocations.clear();
        _recentLocations.addAll(parsedLocations);
      });
    }
  }

  /// Fetches individual ride details to enrich fare, rating, and distance
  /// which are often missing/wrong in the bulk list API response.
  Future<void> _enrichUserRidesFromIds(List<Map<String, dynamic>> rides) async {
    final toEnrich = rides.where((r) {
      final fare = r['fare']?.toString() ?? '—';
      final dist = r['distance']?.toString() ?? '—';
      final rideId = r['rideId']?.toString() ?? '';
      return rideId.isNotEmpty &&
          !rideId.startsWith('ride_') &&
          (fare == '—' || fare.isEmpty || dist == '—' || dist.isEmpty);
    }).toList();

    if (toEnrich.isEmpty) return;
    debugPrint(
      '[UserHistory] Enriching ${toEnrich.length} rides from ride API...',
    );

    bool didUpdate = false;

    for (final ride in toEnrich) {
      final rideId = ride['rideId']!.toString();
      try {
        final res = await ApiService.getRide(rideId);
        if (!res.success) continue;
        final d = res.data;

        // --- Fare ---
        final rawFare =
            d['finalFare'] ?? d['fare'] ?? d['price'] ?? d['estimatedFare'];
        if (rawFare != null) {
          final numStr = rawFare.toString().replaceAll(RegExp(r'[^0-9.]'), '');
          if (numStr.isNotEmpty && numStr != '0') {
            ride['fare'] = '₹$numStr';
            didUpdate = true;
            debugPrint('[UserHistory] $rideId — fare: ₹$numStr');
          }
        }

        // --- Distance ---
        final rawDist = d['distance'] ?? d['distanceKm'] ?? d['distance_km'];
        if (rawDist != null) {
          var dStr = rawDist.toString().trim();
          if (!dStr.toLowerCase().contains('km') &&
              double.tryParse(dStr) != null) {
            dStr = '$dStr km';
          }
          ride['distance'] = dStr;
          didUpdate = true;
        }

        // --- Duration ---
        if (ride['duration'] == '—') {
          final rawDur = d['duration'] ?? d['durationMin'] ?? d['duration_min'];
          if (rawDur != null) {
            var durStr = rawDur.toString().trim();
            if (!durStr.toLowerCase().contains('min') &&
                int.tryParse(durStr) != null) {
              durStr = '$durStr mins';
            }
            ride['duration'] = durStr;
            didUpdate = true;
          }
        }

        // --- Rating (from ride or driver sub-object) ---
        final rawRating = d['rating'];
        if (rawRating != null) {
          final ratingNum = double.tryParse(rawRating.toString());
          if (ratingNum != null && ratingNum > 0) {
            ride['rating'] = ratingNum;
            didUpdate = true;
          }
        }

        // --- Driver name/phone from populated driver object ---
        final driverObj = d['driver'] ?? d['driverId'] ?? d['assignedDriverId'];
        if (driverObj is Map<String, dynamic>) {
          final dName = driverObj['name']?.toString() ?? '';
          if (dName.isNotEmpty && ride['driver'] == 'Driver') {
            ride['driver'] = dName;
            didUpdate = true;
          }
          final dPhone = driverObj['phone']?.toString() ?? '';
          if (dPhone.isNotEmpty && ride['driverPhone'] == '—') {
            ride['driverPhone'] = dPhone;
            didUpdate = true;
          }
          final dVehicle = driverObj['vehicleNumber']?.toString() ?? '';
          if (dVehicle.isNotEmpty && ride['vehicleNumber'] == '—') {
            ride['vehicleNumber'] = dVehicle;
            didUpdate = true;
          }
        }
      } catch (e) {
        debugPrint('[UserHistory] Failed to enrich $rideId: $e');
      }
    }

    if (didUpdate && mounted) {
      setState(() {
        _rideHistoryRecords = List.from(rides);
      });
      debugPrint('[UserHistory] Rides enriched and UI updated.');
    }
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  void dispose() {
    _pendingRideTimer?.cancel();
    _nearbyDriversTimer?.cancel();
    _debounceTimer?.cancel();
    _currentRideTimer?.cancel();
    _pickupCtrl.removeListener(_updatePickupSuggestions);
    _destCtrl.removeListener(_updateDestinationSuggestions);
    _pickupFocusNode.removeListener(_updateSearchFocus);
    _destFocusNode.removeListener(_updateSearchFocus);
    _pickupCtrl.dispose();
    _destCtrl.dispose();
    _pickupFocusNode.dispose();
    _destFocusNode.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  bool get _isSearchFocused =>
      _pickupFocusNode.hasFocus || _destFocusNode.hasFocus;

  void _updateSearchFocus() {
    setState(() {});
  }

  void _updatePickupSuggestions() {
    final query = _pickupCtrl.text.trim();
    if (query.isEmpty) {
      _pickupSelectedText = null; // user cleared — allow suggestions again
      setState(() {
        _pickupSuggestions = [];
        _showPickupSuggestions = false;
      });
      return;
    }

    // If the text was just set by a selection, don't re-fetch predictions
    if (_pickupSelectedText == query) {
      setState(() => _showPickupSuggestions = false);
      return;
    }
    // User modified text after selection — clear the guard
    _pickupSelectedText = null;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _fetchPlacePredictions(query, isPickup: true);
    });
  }

  void _updateDestinationSuggestions() {
    final query = _destCtrl.text.trim();
    if (query.isEmpty) {
      _destSelectedText = null; // user cleared — allow suggestions again
      setState(() {
        _filteredSuggestions = [];
        _showDestinationSuggestions = false;
      });
      return;
    }

    // If the text was just set by a selection, don't re-fetch predictions
    if (_destSelectedText == query) {
      setState(() => _showDestinationSuggestions = false);
      return;
    }
    // User modified text after selection — clear the guard
    _destSelectedText = null;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _fetchPlacePredictions(query, isPickup: false);
    });
  }

  Future<void> _fetchPlacePredictions(
    String query, {
    required bool isPickup,
  }) async {
    if (AppConstants.googlePlacesApiKey.startsWith('YOUR_')) {
      final fallback = _localLocationFallback
          .where((item) => item.toLowerCase().contains(query.toLowerCase()))
          .map((description) => {'description': description, 'place_id': ''})
          .toList();
      setState(() {
        if (isPickup) {
          _pickupSuggestions = fallback;
          _showPickupSuggestions = fallback.isNotEmpty;
        } else {
          _filteredSuggestions = fallback;
          _showDestinationSuggestions = fallback.isNotEmpty;
        }
      });
      return;
    }

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
          'input': query,
          'key': AppConstants.googlePlacesApiKey,
          'components': 'country:in',
        });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final predictions = data['predictions'] as List<dynamic>?;
        final suggestions =
            predictions
                ?.map(
                  (item) => {
                    'description': item['description'] as String? ?? '',
                    'place_id': item['place_id'] as String? ?? '',
                  },
                )
                .where((item) => item['description']!.isNotEmpty)
                .toList() ??
            [];
        setState(() {
          if (isPickup) {
            _pickupSuggestions = suggestions;
            _showPickupSuggestions = suggestions.isNotEmpty;
          } else {
            _filteredSuggestions = suggestions;
            _showDestinationSuggestions = suggestions.isNotEmpty;
          }
        });
      } else {
        setState(() {
          if (isPickup) {
            _pickupSuggestions = [];
            _showPickupSuggestions = false;
          } else {
            _filteredSuggestions = [];
            _showDestinationSuggestions = false;
          }
        });
      }
    } catch (_) {
      final fallback = _localLocationFallback
          .where((item) => item.toLowerCase().contains(query.toLowerCase()))
          .toList();
      setState(() {
        if (isPickup) {
          _pickupSuggestions = fallback
              .map(
                (description) => {'description': description, 'place_id': ''},
              )
              .toList();
          _showPickupSuggestions = fallback.isNotEmpty;
        } else {
          _filteredSuggestions = fallback
              .map(
                (description) => {'description': description, 'place_id': ''},
              )
              .toList();
          _showDestinationSuggestions = fallback.isNotEmpty;
        }
      });
    }
  }

  void _selectPickupLocation(String address) {
    _pickupSelectedText = address.trim(); // suppress re-fetch
    setState(() {
      _pickupCtrl.text = address;
      _pickupSuggestions = [];
      _showPickupSuggestions = false;
    });
    // Update map preview to show selected pickup
    _updateHomeMap();
  }

  Future<void> _selectPickupSuggestion(Map<String, String> suggestion) async {
    final description = suggestion['description'] ?? '';
    if (suggestion['place_id']?.isNotEmpty == true) {
      final resolved = await _fetchPlaceAddressFromPlaceId(
        suggestion['place_id']!,
        fallback: description,
      );
      _selectPickupLocation(resolved);
      return;
    }
    _selectPickupLocation(description);
  }

  Future<void> _selectDestinationSuggestion(
    Map<String, String> suggestion,
  ) async {
    final description = suggestion['description'] ?? '';
    if (suggestion['place_id']?.isNotEmpty == true) {
      final resolved = await _fetchPlaceAddressFromPlaceId(
        suggestion['place_id']!,
        fallback: description,
      );
      _selectDestinationItem(resolved);
      return;
    }
    _selectDestinationItem(description);
  }

  Future<String> _fetchPlaceAddressFromPlaceId(
    String placeId, {
    required String fallback,
  }) async {
    if (AppConstants.googlePlacesApiKey.startsWith('YOUR_')) {
      return fallback;
    }

    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
            'place_id': placeId,
            'key': AppConstants.googlePlacesApiKey,
            'fields': 'formatted_address,name',
            'language': 'en',
          });

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return fallback;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null || result.isEmpty) {
        return fallback;
      }

      return result['formatted_address'] as String? ??
          result['name'] as String? ??
          fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<String> _resolveAddress(String query) async {
    if (query.isEmpty || AppConstants.googlePlacesApiKey.startsWith('YOUR_')) {
      return query;
    }

    final lower = query.toLowerCase();
    if (lower == 'your current location' ||
        lower == 'current location' ||
        lower == context.tr('currentLocation').toLowerCase() ||
        query == _lastGeocodedPickupText ||
        query == _lastGeocodedDestText) {
      return query;
    }

    final resolved = await _fetchFirstPlaceAddress(query);
    return resolved ?? query;
  }

  Future<void> _loadDynamicOptions() async {
    if (mounted && _vehicleTypes.isEmpty) {
      setState(() {
        _loadingCategories = true;
      });
    }

    final dynamicQuickTags = await _loadQuickTags();
    List<Map<String, dynamic>> fetchedTypes = [];

    try {
      final res = await ApiService.getRideCategories();
      debugPrint('📡 [CATEGORIES] success=${res.success} data=${res.data}');

      if (res.success) {
        // Backend may return the list under several different keys.
        // Try them all before giving up.
        List? cats;
        for (final key in [
          'categories',
          'rideCategories',
          'data',
          'items',
          'types',
        ]) {
          if (res.data[key] is List) {
            cats = res.data[key] as List;
            debugPrint('📡 [CATEGORIES] found list under key "$key"');
            break;
          }
        }
        // Some backends return the array at the root level (already unwrapped).
        if (cats == null && res.data.containsKey('data')) {
          final d = res.data['data'];
          if (d is List) cats = d;
        }

        if (cats != null && cats.isNotEmpty) {
          for (final item in cats) {
            if (item is! Map) continue;
            final raw = Map<String, dynamic>.from(item);

            // Backend sends either 'key', 'type', or 'vehicleType' as the ID.
            final String key =
                (raw['key'] ??
                        raw['type'] ??
                        raw['vehicleType'] ??
                        raw['name'] ??
                        '')
                    .toString()
                    .toLowerCase()
                    .trim();

            final String name = (raw['name'] ?? raw['label'] ?? key)
                .toString()
                .trim();

            if (name.isEmpty) continue;

            final String label =
                (raw['description'] ?? raw['subtitle'] ?? raw['label'] ?? '')
                    .toString();

            // Map key → icon
            IconData icon;
            if (key.contains('bike') || key.contains('moto')) {
              icon = Icons.pedal_bike;
            } else if (key.contains('auto') ||
                key.contains('rickshaw') ||
                key.contains('tuk')) {
              icon = Icons.electric_rickshaw;
            } else if (key.contains('ev') || key.contains('electric')) {
              icon = Icons.electric_car;
            } else if (key.contains('luxury') ||
                key.contains('sedan') ||
                name.toLowerCase().contains('sedan')) {
              icon = Icons.directions_car_filled;
            } else if (key.contains('suv')) {
              icon = Icons.airport_shuttle;
            } else {
              icon = Icons.directions_car;
            }

            fetchedTypes.add({
              'name': name,
              'key': key,
              'icon': icon,
              'label': label.isEmpty ? 'Available now' : label,
            });
          }
          debugPrint(
            '📡 [CATEGORIES] Parsed ${fetchedTypes.length} categories from API',
          );
        } else {
          debugPrint(
            '📡 [CATEGORIES] No list found in response — keeping defaults',
          );
        }
      } else {
        debugPrint(
          '📡 [CATEGORIES] API error: ${res.errorMessage} — keeping defaults',
        );
      }
    } catch (e) {
      debugPrint('📡 [CATEGORIES] Exception: $e — keeping defaults');
    }

    if (!mounted) return;
    setState(() {
      _loadingCategories = false;
      if (fetchedTypes.isNotEmpty) {
        _vehicleTypes = fetchedTypes;
        // Preserve selection if it still exists in the new list.
        if (!_vehicleTypes.any((t) => t['name'] == _selectedVehicleType)) {
          _selectedVehicleType = _vehicleTypes.first['name'] as String;
        }
      }
      // fetchedTypes is empty → keep the defaults already set above.
      _serviceOptions = _buildServiceOptions();
      _featureOptions = _buildFeatureOptions();
      _bottomNavItems = _buildBottomNavItems();
      _quickTags = dynamicQuickTags;
    });
  }

  List<Map<String, dynamic>> _buildServiceOptions() {
    return [
      {'name': 'Intercity', 'icon': Icons.airport_shuttle},
      {'name': 'Trip', 'icon': Icons.car_rental},
      {'name': 'Auto', 'icon': Icons.electric_rickshaw},
      {'name': 'Bike', 'icon': Icons.pedal_bike},
      {'name': 'Rentals', 'icon': Icons.watch_later},
      {'name': 'Seniors', 'icon': Icons.elderly},
      {'name': 'Reserve', 'icon': Icons.calendar_month},
    ];
  }

  List<Map<String, dynamic>> _buildFeatureOptions() {
    return [
      {
        'title': 'Map Select',
        'subtitle': 'Pick addresses visually',
        'icon': Icons.map_outlined,
      },
      {
        'title': 'Schedule',
        'subtitle': 'Book for later',
        'icon': Icons.schedule,
      },
      {
        'title': 'Add Stop',
        'subtitle': 'Add a break point',
        'icon': Icons.add_road,
      },
      {
        'title': 'Favorites',
        'subtitle': 'Saved addresses',
        'icon': Icons.star_outlined,
      },
    ];
  }

  List<Map<String, dynamic>> _buildBottomNavItems() {
    return [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.receipt_long_rounded, 'label': 'My Rides'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];
  }

  Future<List<Map<String, dynamic>>> _loadQuickTags() async {
    final defaultTags = <Map<String, dynamic>>[];

    if (AppConstants.googlePlacesApiKey.startsWith('YOUR_')) {
      return defaultTags
          .map(
            (tag) => {
              'icon': tag['icon'],
              'label': tag['label'],
              'address': '${tag['label']} near your current location',
            },
          )
          .toList();
    }

    final List<Map<String, dynamic>> tags = [];
    for (final tag in defaultTags) {
      final address = await _fetchFirstPlaceAddress(tag['query'] as String);
      tags.add({
        'icon': tag['icon'],
        'label': tag['label'],
        'address': address ?? '${tag['label']} near your current location',
      });
    }
    return tags;
  }

  Future<String?> _fetchFirstPlaceAddress(String query) async {
    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
            'query': query,
            'key': AppConstants.googlePlacesApiKey,
            'region': 'in',
            'language': 'en',
          });

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        return null;
      }

      return results.first['formatted_address'] as String? ??
          results.first['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _selectDestinationItem(String address) {
    final entry = _createLocationEntry(address);
    _destSelectedText = address.trim(); // suppress re-fetch

    setState(() {
      _destCtrl.text = address;
      _filteredSuggestions = [];
      _showDestinationSuggestions = false;
      _addToRecentLocations(entry);
    });

    _showInfo('Destination set to "$address"');
    _updateHomeMap();
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    if (address.isEmpty ||
        AppConstants.googlePlacesApiKey.startsWith('YOUR_')) {
      return null;
    }
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'key': AppConstants.googlePlacesApiKey,
      });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final loc =
              results[0]['geometry']['location'] as Map<String, dynamic>;
          return LatLng(loc['lat'] as double, loc['lng'] as double);
        }
      }
    } catch (e) {
      debugPrint('Home map geocode error: $e');
    }
    return null;
  }

  Future<String?> _fetchAddressFromCoordinates(LatLng latLng) async {
    return GeocodingService.reverseGeocode(latLng);
  }

  Future<void> _loadHomeRoute() async {
    _homeRoutePoints = [];
    if (_pickupPoint == null || _destinationPoint == null) return;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_pickupPoint!.latitude},${_pickupPoint!.longitude}'
        '&destination=${_destinationPoint!.latitude},${_destinationPoint!.longitude}'
        '&key=${AppConstants.googlePlacesApiKey}',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final poly = routes[0]['overview_polyline']?['points'] as String?;
          if (poly != null && poly.isNotEmpty) {
            _homeRoutePoints = _decodePolyline(poly);
          }
        }
      }
    } catch (e) {
      debugPrint('Home route load error: $e');
    }
    if (_homeRoutePoints.isEmpty &&
        _pickupPoint != null &&
        _destinationPoint != null) {
      _homeRoutePoints = [_pickupPoint!, _destinationPoint!];
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int result = 0;
      int shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<void> _updateHomeMap() async {
    // Geocode if needed
    if (_pickupCtrl.text.isNotEmpty &&
        _pickupCtrl.text != 'Your Current Location' &&
        _pickupCtrl.text != 'Current location') {
      if (_pickupCtrl.text.trim() != _lastGeocodedPickupText) {
        final geocoded = await _geocodeAddress(_pickupCtrl.text.trim());
        if (geocoded != null) {
          _pickupPoint = geocoded;
          _lastGeocodedPickupText = _pickupCtrl.text.trim();
        }
      }
    }
    if (_destCtrl.text.isNotEmpty) {
      if (_destCtrl.text.trim() != _lastGeocodedDestText) {
        final geocoded = await _geocodeAddress(_destCtrl.text.trim());
        if (geocoded != null) {
          _destinationPoint = geocoded;
          _lastGeocodedDestText = _destCtrl.text.trim();
        }
      }
    }

    // Update markers
    final markers = <Marker>{};
    if (_pickupPoint != null) {
      _mapCenter = _pickupPoint!;
    }
    if (_destinationPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination_home'),
          position: _destinationPoint!,
          infoWindow: InfoWindow(title: _destCtrl.text),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    // Add nearby drivers as custom 3D markers matching their vehicle type
    debugPrint(
      '📍 [HomeMap] Rebuilding map markers. Total nearby drivers list length: ${_nearbyDrivers.length}',
    );
    for (final driver in _nearbyDrivers) {
      final driverLat = (driver['lat'] as num?)?.toDouble();
      final driverLng = (driver['lng'] as num?)?.toDouble();
      if (driverLat != null && driverLng != null) {
        final driverId =
            driver['id']?.toString() ?? driver['_id']?.toString() ?? 'unknown';
        final vehicleType = driver['vehicleType']?.toString() ?? 'Car';
        final icon = await MapUtils.get3DVehicleMarkerForType(vehicleType);
        debugPrint(
          '   - Adding driver marker $driverId ($vehicleType) at coordinates: $driverLat, $driverLng',
        );
        markers.add(
          Marker(
            markerId: MarkerId('driver_nearby_$driverId'),
            position: LatLng(driverLat, driverLng),
            infoWindow: InfoWindow(
              title: driver['name']?.toString() ?? 'Driver',
              snippet:
                  '$vehicleType • ${driver['vehicleNumber']?.toString() ?? ''}',
            ),
            icon: icon,
            flat: false,
          ),
        );
      } else {
        debugPrint(
          '   - Skip driver ${driver['name']} due to missing coordinates: lat=${driver['lat']}, lng=${driver['lng']}',
        );
      }
    }

    _homeMarkers = markers;

    // Load route if both points present
    if (_pickupPoint != null && _destinationPoint != null) {
      await _loadHomeRoute();
    } else {
      _homeRoutePoints = [];
    }

    setState(() {});

    // Fit bounds on map
    if (_mapController != null &&
        (_homeRoutePoints.isNotEmpty || _pickupPoint != null)) {
      final points = _homeRoutePoints.isNotEmpty
          ? _homeRoutePoints
          : ([_pickupPoint, _destinationPoint].whereType<LatLng>().toList());
      if (points.isNotEmpty) {
        if (points.length == 1) {
          try {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(points.first, 15),
            );
          } catch (_) {}
        } else {
          double minLat = points.first.latitude;
          double maxLat = points.first.latitude;
          double minLng = points.first.longitude;
          double maxLng = points.first.longitude;
          for (final p in points) {
            if (p.latitude < minLat) minLat = p.latitude;
            if (p.latitude > maxLat) maxLat = p.latitude;
            if (p.longitude < minLng) minLng = p.longitude;
            if (p.longitude > maxLng) maxLng = p.longitude;
          }
          final bounds = LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          );
          try {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 60),
            );
          } catch (_) {}
        }
      }
    }
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

  void _startNearbyDriversPolling() {
    _nearbyDriversTimer?.cancel();
    _fetchNearbyDrivers();
    _nearbyDriversTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _fetchNearbyDrivers();
      }
    });
  }

  void _stopNearbyDriversPolling() {
    _nearbyDriversTimer?.cancel();
    _nearbyDriversTimer = null;
  }

  Future<void> _fetchNearbyDrivers() async {
    final latLng = _pickupPoint ?? _mapCenter;
    debugPrint(
      '🔍 [HomeMap] Fetching nearby drivers for LatLng: ${latLng.latitude}, ${latLng.longitude}...',
    );
    try {
      final res = await ApiService.getNearbyDrivers(
        lat: latLng.latitude,
        lng: latLng.longitude,
      );
      if (res.success && mounted) {
        final raw =
            res.data['drivers'] as List<dynamic>? ??
            res.data['data'] as List<dynamic>? ??
            [];
        final List<Map<String, dynamic>> list = [];
        for (var d in raw) {
          if (d is Map) {
            list.add(Map<String, dynamic>.from(d));
          }
        }
        debugPrint(
          '✅ [HomeMap] Successfully fetched ${list.length} nearby drivers from backend',
        );
        setState(() {
          _nearbyDrivers = list;
        });
        _updateHomeMap();
      } else {
        debugPrint(
          '⚠️ [HomeMap] Fetch nearby drivers returned failure: ${res.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ [HomeMap] Error fetching nearby drivers: $e');
    }
  }

  Map<String, dynamic> _createLocationEntry(String address) {
    final label = address.split(',').first.trim();
    return {'label': label, 'address': address, 'icon': Icons.location_on};
  }

  void _addToRecentLocations(Map<String, dynamic> entry) {
    _recentLocations.removeWhere((item) => item['address'] == entry['address']);

    _recentLocations.insert(0, entry);
    if (_recentLocations.length > 4) {
      _recentLocations.removeLast();
    }
  }

  void _addToSavedPlaces(Map<String, dynamic> entry) {
    final exists = _savedPlaces.any(
      (item) => item['address'] == entry['address'],
    );
    if (!exists) {
      _savedPlaces.insert(0, entry);
      if (_savedPlaces.length > 3) {
        _savedPlaces.removeLast();
      }
      _savePlaceToBackend(entry);
    }
  }

  Future<void> _savePlaceToBackend(Map<String, dynamic> entry) async {
    try {
      final userId = await SessionService.getUserId() ?? 'guest_user';
      final name = entry['label'] as String? ?? 'Home';
      final address = entry['address'] as String? ?? '';

      // Infer type
      String type = 'other';
      final lowerName = name.toLowerCase();
      if (lowerName.contains('home')) {
        type = 'home';
      } else if (lowerName.contains('work') || lowerName.contains('office')) {
        type = 'work';
      }

      await ApiService.savePlace(
        userId: userId,
        name: name,
        address: address,
        lat: 40.7128,
        lng: -74.0060,
        type: type,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error saving place to backend: $e');
    }
  }

  Future<void> _deletePlaceFromBackend(Map<String, dynamic> place) async {
    try {
      final userId = await SessionService.getUserId() ?? 'guest_user';
      final placeId = place['id']?.toString() ?? '';
      if (placeId.isNotEmpty) {
        await ApiService.deleteSavedPlace(userId: userId, placeId: placeId);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error deleting place from backend: $e');
    }
  }

  // ignore: unused_element
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

    await SessionService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _selectLocationFromMap(
    String title,
    TextEditingController controller,
  ) async {
    final selected = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => MapLocationPickerScreen(title: title)),
    );

    if (selected == null || selected.isEmpty) {
      return;
    }

    if (controller == _pickupCtrl) {
      _selectPickupLocation(selected);
      return;
    }

    if (controller == _destCtrl) {
      _selectDestinationItem(selected);
      return;
    }

    setState(() {
      controller.text = selected;
    });
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Widget _buildQuickTag(IconData icon, String label, String address) {
    return GestureDetector(
      onTap: () => _selectDestinationItem(address),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentStrong.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: AppColors.accentStrong),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLocationPlaceholder(String message) {
    return Container(
      width: double.infinity,

      margin: const EdgeInsets.only(bottom: 14),

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentStrong.withValues(alpha: 0.08),
            AppColors.accentYellow.withValues(alpha: 0.08),
          ],
        ),

        borderRadius: BorderRadius.circular(24),

        border: Border.all(
          color: AppColors.accentStrong.withValues(alpha: 0.15),
          width: 1.2,
        ),

        boxShadow: [
          BoxShadow(
            color: AppColors.accentStrong.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ICON CONTAINER
          Container(
            padding: const EdgeInsets.all(14),

            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accentStrong, AppColors.accentYellow],
              ),

              borderRadius: BorderRadius.circular(18),
            ),

            child: const Icon(
              Icons.location_off_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),

          const SizedBox(width: 16),

          /// TEXT CONTENT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing here yet',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  message,

                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(color: AppColors.border),
                      ),

                      child: Row(
                        children: [
                          Icon(
                            Icons.add_location_alt,
                            size: 14,
                            color: AppColors.accentStrong,
                          ),

                          const SizedBox(width: 6),

                          Text(
                            'Add location',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideHistoryCard(Map<String, dynamic> ride) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark
        ? AppColors.darkOnSurface
        : AppColors.textDark;
    final secondaryTextColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.6)
        : AppColors.textDark.withAlpha(150);
    final cardBgColor = isDark
        ? AppColors.darkSurfaceSoft
        : Theme.of(context).colorScheme.surface;
    final innerCardBgColor = isDark
        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.4)
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : AppColors.textDark.withAlpha(10);
    final borderCol = isDark
        ? AppColors.darkBorder
        : AppColors.accentStrong.withAlpha(30);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with date and fare
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (ctx) {
                      final rawStatus = (ride['rideStatus'] ?? 'completed')
                          .toString()
                          .toLowerCase();
                      final String statusLabel;
                      final Color statusColor;
                      if (rawStatus == 'completed' || rawStatus == 'ended') {
                        statusLabel = 'Ride Completed';
                        statusColor = AppColors.secondary;
                      } else if (rawStatus == 'started' ||
                          rawStatus == 'ongoing' ||
                          rawStatus == 'in_progress') {
                        statusLabel = 'Ongoing';
                        statusColor = AppColors.accentStrong;
                      } else if (rawStatus == 'accepted' ||
                          rawStatus == 'assigned') {
                        statusLabel = 'Driver Assigned';
                        statusColor = AppColors.accentStrong;
                      } else if (rawStatus == 'pending' ||
                          rawStatus == 'requested') {
                        statusLabel = 'Looking for Driver';
                        statusColor = AppColors.accentYellow;
                      } else if (rawStatus == 'cancelled' ||
                          rawStatus == 'canceled') {
                        statusLabel = 'Cancelled';
                        statusColor = AppColors.accentRed;
                      } else {
                        statusLabel =
                            rawStatus[0].toUpperCase() + rawStatus.substring(1);
                        statusColor = secondaryTextColor;
                      }
                      return Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: AppTextStyles.subtitle.copyWith(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ride['date'] as String? ?? '—',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  if ((ride['time'] as String? ?? '—') != '—') ...[
                    const SizedBox(height: 2),
                    Text(
                      ride['time'] as String,
                      style: AppTextStyles.subtitle.copyWith(
                        fontSize: 11,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentStrong.withAlpha(20),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      ride['fare'] as String? ?? '—',
                      style: AppTextStyles.cardTitle.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentStrong,
                      ),
                    ),
                  ),
                  if ((ride['rideId'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'ID: ${(ride['rideId'] as String).substring(0, (ride['rideId'] as String).length > 8 ? 8 : (ride['rideId'] as String).length)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.darkOnSurface.withValues(alpha: 0.5)
                            : AppColors.textDark.withAlpha(120),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Driver details card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: innerCardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accentStrong.withAlpha(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accentStrong.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 20,
                    color: AppColors.accentStrong,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver',
                        style: AppTextStyles.subtitle.copyWith(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ride['driver'] as String? ?? 'N/A',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColors.accentYellow,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ride['rating']}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Vehicle details
          if ((ride['vehicleNumber'] as String? ?? '—') != '—')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: innerCardBgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accentStrong.withAlpha(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car_rounded,
                    size: 18,
                    color: AppColors.accentStrong,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${ride['vehicleType'] ?? '—'} • ${ride['vehicleNumber'] ?? '—'}',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 0),
          const SizedBox(height: 14),

          // Pickup location
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pickup',
                      style: AppTextStyles.subtitle.copyWith(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ride['pickup'] as String,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkOnSurface
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.9),
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

          // Dropoff location
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 18,
                  color: AppColors.accentRed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dropoff',
                      style: AppTextStyles.subtitle.copyWith(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ride['dropoff'] as String,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkOnSurface
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.9),
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

          // Details row: Distance and Ride Type
          Row(
            children: [
              Expanded(
                child: _buildDetailChip(
                  Icons.straighten,
                  ride['distance'] as String? ?? '—',
                  'Distance',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDetailChip(
                  Icons.directions_car,
                  ride['vehicleType'] as String? ?? '—',
                  'Vehicle Type',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String value, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final innerCardBgColor = isDark
        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.4)
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: innerCardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentStrong.withAlpha(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.accentStrong),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkOnSurface
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.subtitle.copyWith(
              fontSize: 10,
              color: isDark
                  ? AppColors.darkOnSurface.withValues(alpha: 0.5)
                  : AppColors.textDark.withAlpha(130),
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseHistoryDate(Map<String, dynamic> ride) {
    // Prefer raw ISO timestamp for accuracy
    final isoStr = ride['createdAt'] as String?;
    if (isoStr != null && isoStr.isNotEmpty) {
      try {
        return DateTime.parse(isoStr).toLocal();
      } catch (_) {}
    }
    // Fallback: parse formatted date string (e.g. "Jun 9, 2026")
    final dateStr = ride['date'] as String?;
    if (dateStr == null || dateStr.isEmpty || dateStr == '—') return null;
    try {
      // Handle "Jun 9, 2026" format (produced by _formatDate)
      final cleaned = dateStr.replaceAll(',', '').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      if (parts.length == 3) {
        final monthStr = parts[0].toLowerCase().substring(0, 3);
        final day = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);
        const months = [
          'jan',
          'feb',
          'mar',
          'apr',
          'may',
          'jun',
          'jul',
          'aug',
          'sep',
          'oct',
          'nov',
          'dec',
        ];
        final monthIdx = months.indexOf(monthStr);
        if (day != null && monthIdx != -1 && year != null) {
          return DateTime(year, monthIdx + 1, day);
        }
      }
    } catch (_) {}
    return null;
  }

  double _parseHistoryFare(Map<String, dynamic> ride) {
    final fareStr = ride['fare'] as String?;
    if (fareStr == null || fareStr.isEmpty || fareStr == '—') return 0.0;
    final cleanStr = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? 0.0;
  }

  double _parseHistoryDistance(Map<String, dynamic> ride) {
    final distStr = ride['distance'] as String?;
    if (distStr == null || distStr.isEmpty || distStr == '—') return 0.0;
    final cleanStr = distStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? 0.0;
  }

  List<Map<String, dynamic>> get _filteredAndSortedUserRides {
    List<Map<String, dynamic>> results = List.from(_rideHistoryRecords);

    // 1. Search Query
    if (_historySearchQuery.isNotEmpty) {
      final query = _historySearchQuery.toLowerCase();
      results = results.where((t) {
        final pickup = (t['pickup'] ?? '').toString().toLowerCase();
        final dropoff = (t['dropoff'] ?? '').toString().toLowerCase();
        final driver = (t['driver'] ?? '').toString().toLowerCase();
        final rideId = (t['rideId'] ?? '').toString().toLowerCase();
        return pickup.contains(query) ||
            dropoff.contains(query) ||
            driver.contains(query) ||
            rideId.contains(query);
      }).toList();
    }

    // 2. Ride Type Filter
    if (_historySelectedRideType != 'All') {
      results = results.where((t) {
        final vType = (t['vehicleType'] ?? '').toString().toLowerCase();
        final selectedType = _historySelectedRideType.toLowerCase();
        return vType.contains(selectedType) || selectedType.contains(vType);
      }).toList();
    }

    // 3. Date Filter
    if (_historySelectedDateOption != 'All Time') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      results = results.where((t) {
        final dt = _parseHistoryDate(t);
        if (dt == null) return false;

        final tripDay = DateTime(dt.year, dt.month, dt.day);

        switch (_historySelectedDateOption) {
          case 'Today':
            return tripDay.isAtSameMomentAs(today);
          case 'Yesterday':
            return tripDay.isAtSameMomentAs(
              today.subtract(const Duration(days: 1)),
            );
          case 'Last 7 Days':
            return dt.isAfter(now.subtract(const Duration(days: 7)));
          case 'Last 30 Days':
            return dt.isAfter(now.subtract(const Duration(days: 30)));
          case 'Custom':
            if (_historyCustomDateRange == null) return true;
            final start = DateTime(
              _historyCustomDateRange!.start.year,
              _historyCustomDateRange!.start.month,
              _historyCustomDateRange!.start.day,
            );
            final end = DateTime(
              _historyCustomDateRange!.end.year,
              _historyCustomDateRange!.end.month,
              _historyCustomDateRange!.end.day,
              23,
              59,
              59,
            );
            return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
                dt.isBefore(end.add(const Duration(seconds: 1)));
          default:
            return true;
        }
      }).toList();
    }

    // 4. Fare Filter
    if (_historySelectedFareOption != 'All') {
      results = results.where((t) {
        final fare = _parseHistoryFare(t);
        switch (_historySelectedFareOption) {
          case 'High (> ₹200)':
            return fare > 200;
          case 'Medium (₹100-₹200)':
            return fare >= 100 && fare <= 200;
          case 'Low (< ₹100)':
            return fare < 100 && fare > 0;
          default:
            return true;
        }
      }).toList();
    }

    // 5. Sorting
    results.sort((a, b) {
      switch (_historySortBy) {
        case 'Oldest':
          final dtA = _parseHistoryDate(a) ?? DateTime(1970);
          final dtB = _parseHistoryDate(b) ?? DateTime(1970);
          return dtA.compareTo(dtB);

        case 'Fare: High to Low':
          return _parseHistoryFare(b).compareTo(_parseHistoryFare(a));

        case 'Fare: Low to High':
          return _parseHistoryFare(a).compareTo(_parseHistoryFare(b));

        case 'Distance: Longest':
          return _parseHistoryDistance(b).compareTo(_parseHistoryDistance(a));

        case 'Newest':
        default:
          final dtA = _parseHistoryDate(a) ?? DateTime(1970);
          final dtB = _parseHistoryDate(b) ?? DateTime(1970);
          return dtB.compareTo(dtA);
      }
    });

    return results;
  }

  int _getHistoryActiveFiltersCount() {
    int count = 0;
    if (_historySortBy != 'Newest') count++;
    if (_historySelectedRideType != 'All') count++;
    if (_historySelectedDateOption != 'All Time') count++;
    if (_historySelectedFareOption != 'All') count++;
    return count;
  }

  void _resetHistoryFilters() {
    setState(() {
      _historySearchQuery = '';
      _historySearchController.clear();
      _historySortBy = 'Newest';
      _historySelectedRideType = 'All';
      _historySelectedDateOption = 'All Time';
      _historyCustomDateRange = null;
      _historySelectedFareOption = 'All';
    });
  }

  List<String> get _historyRideTypes {
    final types = _rideHistoryRecords
        .map((t) => t['vehicleType'] as String? ?? '')
        .where((t) => t.isNotEmpty && t != '—')
        .toSet()
        .toList();
    types.sort();
    return ['All', ...types];
  }

  void _showHistoryFiltersBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final green = AppColors.accentStrong;

    String localSortBy = _historySortBy;
    String localRideType = _historySelectedRideType;
    String localDateOption = _historySelectedDateOption;
    DateTimeRange? localCustomDateRange = _historyCustomDateRange;
    String localFareOption = _historySelectedFareOption;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final showCustomDatePickerButton = localDateOption == 'Custom';
            final hasAnyActive =
                localSortBy != 'Newest' ||
                localRideType != 'All' ||
                localDateOption != 'All Time' ||
                localFareOption != 'All';

            return Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: border)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter & Sort',
                          style: AppTextStyles.heading.copyWith(
                            fontSize: 18,
                            color: textPri,
                          ),
                        ),
                        if (hasAnyActive)
                          GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                localSortBy = 'Newest';
                                localRideType = 'All';
                                localDateOption = 'All Time';
                                localCustomDateRange = null;
                                localFareOption = 'All';
                              });
                            },
                            child: Text(
                              'Reset All',
                              style: TextStyle(
                                color: AppColors.accentRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sort By',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            'Newest',
                            'Oldest',
                            'Fare: High to Low',
                            'Fare: Low to High',
                            'Distance: Longest',
                          ].map((sortOption) {
                            final isSelected = localSortBy == sortOption;
                            return ChoiceChip(
                              label: Text(sortOption),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setSheetState(() {
                                    localSortBy = sortOption;
                                  });
                                }
                              },
                              selectedColor: green.withAlpha(40),
                              backgroundColor: border.withAlpha(20),
                              labelStyle: TextStyle(
                                color: isSelected ? green : textPri,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? green
                                    : border.withAlpha(60),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Ride Type',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _historyRideTypes.map((type) {
                        final isSelected = localRideType == type;
                        return ChoiceChip(
                          label: Text(type),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setSheetState(() {
                                localRideType = type;
                              });
                            }
                          },
                          selectedColor: green.withAlpha(40),
                          backgroundColor: border.withAlpha(20),
                          labelStyle: TextStyle(
                            color: isSelected ? green : textPri,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected ? green : border.withAlpha(60),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Date Completed',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            'All Time',
                            'Today',
                            'Yesterday',
                            'Last 7 Days',
                            'Last 30 Days',
                            'Custom',
                          ].map((opt) {
                            final isSelected = localDateOption == opt;
                            return ChoiceChip(
                              label: Text(opt),
                              selected: isSelected,
                              onSelected: (selected) async {
                                if (selected) {
                                  setSheetState(() {
                                    localDateOption = opt;
                                  });
                                  if (opt == 'Custom') {
                                    final range = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 1),
                                      ),
                                      initialDateRange: localCustomDateRange,
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme: Theme.of(context)
                                                .colorScheme
                                                .copyWith(
                                                  primary: green,
                                                  onPrimary: Colors.white,
                                                  surface: surface,
                                                  onSurface: textPri,
                                                ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (range != null) {
                                      setSheetState(() {
                                        localCustomDateRange = range;
                                      });
                                    } else {
                                      if (localCustomDateRange == null) {
                                        setSheetState(() {
                                          localDateOption = 'All Time';
                                        });
                                      }
                                    }
                                  }
                                }
                              },
                              selectedColor: green.withAlpha(40),
                              backgroundColor: border.withAlpha(20),
                              labelStyle: TextStyle(
                                color: isSelected ? green : textPri,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? green
                                    : border.withAlpha(60),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }).toList(),
                    ),
                    if (showCustomDatePickerButton &&
                        localCustomDateRange != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: green.withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: green.withAlpha(50)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Selected: ${localCustomDateRange!.start.day}/${localCustomDateRange!.start.month}/${localCustomDateRange!.start.year} - ${localCustomDateRange!.end.day}/${localCustomDateRange!.end.month}/${localCustomDateRange!.end.year}',
                              style: TextStyle(
                                color: green,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final range = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 1),
                                  ),
                                  initialDateRange: localCustomDateRange,
                                );
                                if (range != null) {
                                  setSheetState(() {
                                    localCustomDateRange = range;
                                  });
                                }
                              },
                              child: Icon(
                                Icons.edit_outlined,
                                color: green,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Fare Range',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            'All',
                            'Low (< ₹100)',
                            'Medium (₹100-₹200)',
                            'High (> ₹200)',
                          ].map((opt) {
                            final isSelected = localFareOption == opt;
                            return ChoiceChip(
                              label: Text(opt),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setSheetState(() {
                                    localFareOption = opt;
                                  });
                                }
                              },
                              selectedColor: green.withAlpha(40),
                              backgroundColor: border.withAlpha(20),
                              labelStyle: TextStyle(
                                color: isSelected ? green : textPri,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? green
                                    : border.withAlpha(60),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _historySortBy = localSortBy;
                            _historySelectedRideType = localRideType;
                            _historySelectedDateOption = localDateOption;
                            _historyCustomDateRange = localCustomDateRange;
                            _historySelectedFareOption = localFareOption;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Apply Filters',
                          style: AppTextStyles.button.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistorySearchHeader(
    BuildContext context,
    Color surface,
    Color cardSoft,
    Color border,
    Color textPri,
    Color textSec,
    Color green,
  ) {
    final activeFiltersCount = _getHistoryActiveFiltersCount();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cardSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: TextField(
                  controller: _historySearchController,
                  onChanged: (val) {
                    setState(() {
                      _historySearchQuery = val;
                    });
                  },
                  style: TextStyle(color: textPri, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search pickup, drop, driver...',
                    hintStyle: TextStyle(color: textSec, fontSize: 13),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: textSec,
                      size: 20,
                    ),
                    suffixIcon: _historySearchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _historySearchController.clear();
                              setState(() {
                                _historySearchQuery = '';
                              });
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: textSec,
                              size: 20,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _showHistoryFiltersBottomSheet,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: activeFiltersCount > 0
                          ? green.withAlpha(25)
                          : cardSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: activeFiltersCount > 0
                            ? green.withAlpha(120)
                            : border,
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      color: activeFiltersCount > 0 ? green : textPri,
                      size: 22,
                    ),
                  ),
                  if (activeFiltersCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$activeFiltersCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildHistoryFilterPill(
                icon: Icons.swap_vert_rounded,
                label: 'Sort: $_historySortBy',
                isActive: _historySortBy != 'Newest',
                onTap: _showHistoryFiltersBottomSheet,
                green: green,
                border: border,
                cardSoft: cardSoft,
                textSec: textSec,
                textPri: textPri,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterPill(
                icon: Icons.directions_car_outlined,
                label: _historySelectedRideType == 'All'
                    ? 'Ride Type'
                    : _historySelectedRideType,
                isActive: _historySelectedRideType != 'All',
                onTap: _showHistoryFiltersBottomSheet,
                green: green,
                border: border,
                cardSoft: cardSoft,
                textSec: textSec,
                textPri: textPri,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterPill(
                icon: Icons.date_range_outlined,
                label:
                    _historySelectedDateOption == 'Custom' &&
                        _historyCustomDateRange != null
                    ? '${_historyCustomDateRange!.start.day}/${_historyCustomDateRange!.start.month} - ${_historyCustomDateRange!.end.day}/${_historyCustomDateRange!.end.month}'
                    : _historySelectedDateOption == 'All Time'
                    ? 'Date'
                    : _historySelectedDateOption,
                isActive: _historySelectedDateOption != 'All Time',
                onTap: _showHistoryFiltersBottomSheet,
                green: green,
                border: border,
                cardSoft: cardSoft,
                textSec: textSec,
                textPri: textPri,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterPill(
                icon: Icons.payments_outlined,
                label: _historySelectedFareOption == 'All'
                    ? 'Fare'
                    : _historySelectedFareOption,
                isActive: _historySelectedFareOption != 'All',
                onTap: _showHistoryFiltersBottomSheet,
                green: green,
                border: border,
                cardSoft: cardSoft,
                textSec: textSec,
                textPri: textPri,
              ),
              if (activeFiltersCount > 0 || _historySearchQuery.isNotEmpty) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _resetHistoryFilters,
                  child: Text(
                    'Clear All',
                    style: TextStyle(
                      color: AppColors.accentRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryFilterPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color green,
    required Color border,
    required Color cardSoft,
    required Color textSec,
    required Color textPri,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? green.withAlpha(20) : cardSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? green.withAlpha(120) : border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? green : textSec),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? green : textPri,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: isActive ? green : textSec,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final cardSoft = isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final textSec = isDark ? AppColors.textLight : AppColors.textGrey;
    final green = AppColors.accentStrong;

    final ridesToShow = _filteredAndSortedUserRides;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ride history', style: AppTextStyles.heading),
            const SizedBox(height: 10),
            Text(
              'Your recent rides and driver ratings at a glance.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 20),
            _buildHistorySearchHeader(
              context,
              surface,
              cardSoft,
              border,
              textPri,
              textSec,
              green,
            ),
            const SizedBox(height: 24),
            if (_loadingRides)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                    color: AppColors.accentStrong,
                  ),
                ),
              )
            else if (_ridesError != null)
              _buildEmptyLocationPlaceholder(
                'Failed to load history: $_ridesError',
              )
            else if (_rideHistoryRecords.isEmpty)
              _buildEmptyLocationPlaceholder(
                'No completed rides yet. Book a ride to see your history here.',
              )
            else if (ridesToShow.isEmpty)
              _buildEmptyLocationPlaceholder(
                'No rides matches your active filter criteria. Try clearing them.',
              )
            else
              Column(children: ridesToShow.map(_buildRideHistoryCard).toList()),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildServiceCard(Map<String, dynamic> service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.accentStrong.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(
              service['icon'] as IconData,
              color: AppColors.accentStrong,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            service['name'] as String,
            style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _bottomNavIndex == 1
          ? _buildActivityContent()
          : _bottomNavIndex == 2
          ? UserProfileScreen(
              onLogout: _logout,
              onTabChanged: (index) {
                setState(() {
                  _bottomNavIndex = index;
                });
                if (index == 1) {
                  _fetchUserRides();
                }
              },
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo left-aligned in header
                        ChalChalGadiLogo(size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Hello,', style: AppTextStyles.subtitle),
                                  if (_userName.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _userName,
                                        style: AppTextStyles.subtitle.copyWith(
                                          color: AppColors.accentStrong,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Book your ride',
                                style: AppTextStyles.heading,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const LanguageToggleButton(),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: AppTheme.themeMode,
                          builder: (context, themeMode, child) {
                            final isDark =
                                themeMode == ThemeMode.dark ||
                                (themeMode == ThemeMode.system &&
                                    MediaQuery.of(context).platformBrightness ==
                                        Brightness.dark);
                            return GestureDetector(
                              onTap: AppTheme.toggleMode,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.textDark.withAlpha(12),
                                      blurRadius: 14,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isDark ? Icons.wb_sunny : Icons.nights_stay,
                                  color: AppColors.accentStrong,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_pendingRide != null) ...[
                      _buildPendingRideBanner(_pendingRide!),
                      const SizedBox(height: 16),
                    ],
                    // ── Promotional banners (from API) ────────────────────
                    HomeBannerCarousel(fetchBanners: ApiService.getUserBanners),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Ride categories',
                          style: AppTextStyles.heading.copyWith(fontSize: 16),
                        ),
                        // Subtle spinner while the API call is in-flight
                        if (_loadingCategories)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentStrong,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // While loading show skeleton placeholders so the layout
                    // doesn't jump. Once loaded, switch to real category cards.
                    _loadingCategories && _vehicleTypes.isEmpty
                        ? Row(
                            children: List.generate(3, (i) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _buildCategoryShimmer(),
                                ),
                              );
                            }),
                          )
                        : Row(
                            children: _vehicleTypes.map((type) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _buildRideCategoryCard(type),
                                ),
                              );
                            }).toList(),
                          ),
                    const SizedBox(height: 20),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).cardColor.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _isSearchFocused
                              ? AppColors.secondary.withValues(alpha: 0.24)
                              : AppColors.surfaceLight,
                          width: _isSearchFocused ? 1.6 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.textDark.withAlpha(
                              _isSearchFocused ? 14 : 10,
                            ),
                            blurRadius: _isSearchFocused ? 28 : 22,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Book a ride in seconds',
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentYellow.withAlpha(30),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.star,
                                      color: AppColors.accentYellow,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Premium',
                                      style: TextStyle(
                                        color: AppColors.textDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      hint: context.tr('enterPickup'),
                                      prefixIcon: Icons.my_location,
                                      controller: _pickupCtrl,
                                      focusNode: _pickupFocusNode,
                                      keyboardType: TextInputType.text,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => _selectLocationFromMap(
                                      context.tr('pickUpFrom'),
                                      _pickupCtrl,
                                    ),
                                    child: Container(
                                      height: 56,
                                      width: 56,
                                      decoration: BoxDecoration(
                                        color: AppColors.accentStrong,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.accentStrong
                                                .withAlpha(30),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.map,
                                        color: AppColors.surface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_showPickupSuggestions)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Pickup suggestions',
                                      style: AppTextStyles.subtitle.copyWith(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.75),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      margin: const EdgeInsets.only(top: 0),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.textDark.withAlpha(
                                              12,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: _pickupSuggestions.map((
                                          suggestion,
                                        ) {
                                          return InkWell(
                                            onTap: () =>
                                                _selectPickupSuggestion(
                                                  suggestion,
                                                ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14,
                                                  ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.location_on,
                                                    size: 18,
                                                    color:
                                                        AppColors.accentYellow,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      suggestion['description'] ??
                                                          '',
                                                      style: AppTextStyles.body
                                                          .copyWith(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      hint: context.tr('enterDest'),
                                      prefixIcon: Icons.search,
                                      controller: _destCtrl,
                                      focusNode: _destFocusNode,
                                      keyboardType: TextInputType.text,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => _selectLocationFromMap(
                                      context.tr('whereTo'),
                                      _destCtrl,
                                    ),
                                    child: Container(
                                      height: 56,
                                      width: 56,
                                      decoration: BoxDecoration(
                                        color: AppColors.accentStrong,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.accentStrong
                                                .withAlpha(30),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.map,
                                        color: AppColors.surface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_showDestinationSuggestions)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Search suggestions',
                                      style: AppTextStyles.subtitle.copyWith(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.75),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      margin: const EdgeInsets.only(top: 0),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.textDark.withAlpha(
                                              12,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: _filteredSuggestions.map((
                                          suggestion,
                                        ) {
                                          return InkWell(
                                            onTap: () =>
                                                _selectDestinationSuggestion(
                                                  suggestion,
                                                ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14,
                                                  ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.location_on,
                                                    size: 18,
                                                    color:
                                                        AppColors.accentYellow,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      suggestion['description'] ??
                                                          '',
                                                      style: AppTextStyles.body
                                                          .copyWith(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _quickTags.map((tag) {
                              return _buildQuickTag(
                                tag['icon'] as IconData,
                                tag['label'] as String,
                                tag['address'] as String,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                          CustomButton(
                            label: context.tr('chooseRide'),
                            color: AppColors.accentStrong,
                            onPressed: _proceedToSelectRide,
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              height: 320,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: _supportsMap
                                        ? GoogleMap(
                                            onMapCreated:
                                                (
                                                  GoogleMapController
                                                  controller,
                                                ) {
                                                  _mapController = controller;
                                                  // Ensure the map centers to dynamic center
                                                  _mapController!.moveCamera(
                                                    CameraUpdate.newLatLngZoom(
                                                      _mapCenter,
                                                      15,
                                                    ),
                                                  );
                                                },
                                            initialCameraPosition:
                                                CameraPosition(
                                                  target: _mapCenter,
                                                  zoom: 15,
                                                ),
                                            mapType: MapType.normal,
                                            markers: _homeMarkers,
                                            polylines:
                                                _homeRoutePoints.isNotEmpty
                                                ? {
                                                    Polyline(
                                                      polylineId:
                                                          const PolylineId(
                                                            'home_route',
                                                          ),
                                                      points: _homeRoutePoints,
                                                      color: AppColors
                                                          .accentStrong,
                                                      width: 5,
                                                    ),
                                                  }
                                                : <Polyline>{},
                                            myLocationEnabled: true,
                                            myLocationButtonEnabled: false,
                                            zoomControlsEnabled: false,
                                            gestureRecognizers:
                                                <
                                                  Factory<
                                                    OneSequenceGestureRecognizer
                                                  >
                                                >{
                                                  Factory<
                                                    OneSequenceGestureRecognizer
                                                  >(
                                                    () =>
                                                        EagerGestureRecognizer(),
                                                  ),
                                                },
                                          )
                                        : Container(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.map_outlined,
                                                    color:
                                                        AppColors.accentStrong,
                                                    size: 64,
                                                  ),
                                                  const SizedBox(height: 18),
                                                  Text(
                                                    'Map preview unavailable here',
                                                    textAlign: TextAlign.center,
                                                    style: AppTextStyles.heading
                                                        .copyWith(fontSize: 16),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Use the mobile app for live map interaction.',
                                                    textAlign: TextAlign.center,
                                                    style: AppTextStyles.body
                                                        .copyWith(
                                                          color: AppColors
                                                              .textGrey,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
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
                                  if (_supportsMap)
                                    Positioned(
                                      top: 14,
                                      right: 14,
                                      child: GestureDetector(
                                        onTap: () async {
                                          await _initializeCurrentLocation();
                                          if (_mapController != null &&
                                              _pickupPoint != null) {
                                            _mapController!.animateCamera(
                                              CameraUpdate.newLatLng(
                                                _pickupPoint!,
                                              ),
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
                                                color: Colors.black.withAlpha(
                                                  20,
                                                ),
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
                                  if (_supportsMap)
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
                                                color: Colors.black.withAlpha(
                                                  20,
                                                ),
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
                                  if (_supportsMap)
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
                                                color: Colors.black.withAlpha(
                                                  20,
                                                ),
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
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _bottomNavItems.isEmpty
          ? null
          : BottomNavigationBar(
              currentIndex: _bottomNavIndex,
              onTap: (index) {
                setState(() {
                  _bottomNavIndex = index;
                });
                if (index == 1) {
                  _fetchUserRides();
                }
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.accentStrong,
              unselectedItemColor: AppColors.textGrey,
              items: _bottomNavItems.map((item) {
                final String rawLabel = item['label'] as String;
                String labelText = rawLabel;
                if (rawLabel == 'Home') {
                  labelText = context.tr('home');
                } else if (rawLabel == 'My Rides') {
                  labelText = context.tr('myRides');
                } else if (rawLabel == 'Profile') {
                  labelText = context.tr('profile');
                }
                return BottomNavigationBarItem(
                  icon: Icon(item['icon'] as IconData),
                  label: labelText,
                );
              }).toList(),
            ),
    );
  }
}
