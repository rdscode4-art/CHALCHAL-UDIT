import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lottie/lottie.dart' as lottie;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/map_utils.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_service.dart';
import 'drivers_list_screen.dart';
import '../../../services/category_service.dart';
import '../../../models/category_model.dart';
import '../../../core/localization/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Centralised theme-aware colour resolver — keeps every widget clean.
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  final bool dark;
  const _C(this.dark);

  // Scaffold / page background
  Color get scaffold => dark ? AppColors.darkBackground : AppColors.background;

  // AppBar
  Color get appBar => dark ? AppColors.darkSurface : Colors.white;
  Color get appBarTitle => dark ? AppColors.darkOnSurface : AppColors.textDark;

  // Cards / surfaces
  Color get card => dark ? AppColors.darkSurface : Colors.white;
  Color get cardSoft =>
      dark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
  Color get border => dark ? AppColors.darkBorder : AppColors.border;

  // Text
  Color get textPrimary => dark ? AppColors.darkOnSurface : AppColors.textDark;
  Color get textSecondary => dark
      ? AppColors.darkOnSurface.withAlpha((0.7 * 255).round())
      : AppColors.textGrey;

  // Accent — always logo green / yellow / red
  Color get green => AppColors.secondary; // #43A047
  Color get yellow => AppColors.accentYellow; // #FDD835
  Color get red => AppColors.accentRed; // #E53935

  // Icon box inside ride card (unselected)
  Color get iconBoxBg => dark
      ? AppColors.darkSurfaceSoft
      : AppColors.secondary.withAlpha((0.10 * 255).round());

  // Searching overlay card
  Color get overlayCard => dark ? AppColors.darkSurface : Colors.white;
  Color get overlayText => dark ? AppColors.darkOnSurface : AppColors.textDark;
}

String _mapRideTypeToEnum(String rideName) {
  final name = rideName.toLowerCase().trim();
  if (name == 'sedan ac' || name == 'luxury') return 'luxury';
  if (name == 'car') return 'car';
  if (name == 'ev') return 'ev';
  if (name == 'auto') return 'auto';
  if (name == 'bike') return 'bike';
  return name;
}

// ─────────────────────────────────────────────────────────────────────────────
// Choose Your Ride screen
// ─────────────────────────────────────────────────────────────────────────────
class SelectRideScreen extends StatefulWidget {
  final String pickup;
  final String destination;
  final String vehicleType;
  final LatLng? pickupLatLng;
  final LatLng? destinationLatLng;

  const SelectRideScreen({
    super.key,
    required this.pickup,
    required this.destination,
    required this.vehicleType,
    this.pickupLatLng,
    this.destinationLatLng,
  });

  @override
  State<SelectRideScreen> createState() => _SelectRideScreenState();
}

class _SelectRideScreenState extends State<SelectRideScreen> {
  int _selected = 0;

  bool _isSearching = false;
  bool _driverFound = false;

  bool isLoadingRoute = true;

  List<LatLng> routePoints = [];

  double distanceKm = 0;
  double durationMin = 0;

  LatLng? pickupPoint;
  LatLng? destinationPoint;

  GoogleMapController? _mapController;

  List<Map<String, dynamic>> _dynamicRides = [];
  bool _loadingCategories = true;

  List<Map<String, dynamic>> get _rides => _dynamicRides;
  List<Map<String, dynamic>> get _filteredRides {
    if (widget.vehicleType.isEmpty) return _rides;
    
    final filtered = _rides.where((r) => 
      r['category']?.toString().toLowerCase() == widget.vehicleType.toLowerCase() ||
      r['vehicleType']?.toString().toLowerCase() == widget.vehicleType.toLowerCase() ||
      r['name']?.toString().toLowerCase() == widget.vehicleType.toLowerCase()
    ).toList();
    
    return filtered.isNotEmpty ? filtered : _rides;
  }

  String _formatEta(String? eta) {
    if (eta == null || eta.isEmpty) return '';
    final match = RegExp(r'^(\d+)\s*mins?\s*away$').firstMatch(eta.trim());
    if (match != null) {
      return '${match.group(1)} ${context.tr('minsAway')}';
    }
    return eta;
  }

  String _localizedRideDetail(String? detail) {
    if (detail == null || detail.isEmpty) return context.tr('premiumRide');
    if (detail == 'Premium ride') return context.tr('premiumRide');
    return detail;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    // Also populate the shared CategoryService cache for vehicle images,
    // then rebuild ride cards once images are available.
    CategoryService.instance.fetchCategories(role: 'user').then((_) {
      if (mounted) setState(() {});
    });
    loadRoute();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final List<CategoryModel> cats = await CategoryService.instance.getOrFetch(role: 'user');
      final List<Map<String, dynamic>> fetchedRides = [];
      for (var item in cats) {
        final String key = item.key;
        final String name = item.name;
        final String detail = item.description;
        IconData icon = Icons.directions_car;

        if (key == 'bike') {
          icon = Icons.pedal_bike;
        } else if (key == 'auto') {
          icon = Icons.electric_rickshaw;
        } else if (key == 'ev') {
          icon = Icons.electric_car;
        } else if (key == 'luxury' || name.toLowerCase().contains('sedan')) {
          icon = Icons.directions_car_filled;
        } else if (key == 'car') {
          icon = Icons.directions_car;
        }

        fetchedRides.add({
          'category': key,
          'vehicleType': key,
          'name': name,
          'icon': icon,
          'price': 'Discuss',
          'detail': detail,
          'dropTime': 'Drop soon',
        });
      }
      if (fetchedRides.isNotEmpty) {
        setState(() {
          _dynamicRides = fetchedRides;
          final matchIndex = _dynamicRides.indexWhere(
            (r) =>
                r['category']?.toString().toLowerCase() ==
                    widget.vehicleType.toLowerCase() ||
                r['vehicleType']?.toString().toLowerCase() ==
                    widget.vehicleType.toLowerCase() ||
                r['name']?.toString().toLowerCase() ==
                    widget.vehicleType.toLowerCase(),
          );
          // Since _filteredRides only returns the matched item, the selected index should always be 0.
          if (matchIndex != -1) {
            _selected = 0; 
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading categories in SelectRideScreen: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingCategories = false);
      }
    }
  }

  Future<void> loadRoute() async {
    setState(() => isLoadingRoute = true);

    const fallbackA = LatLng(28.6139, 77.2090);
    const fallbackB = LatLng(28.7041, 77.1025);

    pickupPoint = widget.pickupLatLng ?? await MapUtils.geocode(widget.pickup) ?? fallbackA;
    destinationPoint = widget.destinationLatLng ?? await MapUtils.geocode(widget.destination) ?? fallbackB;

    final result = await MapUtils.getDirections(
      origin: pickupPoint!,
      destination: destinationPoint!,
    );

    routePoints = result.points;
    distanceKm = result.distanceKm;
    durationMin = result.durationMin;

    // Fallback distances if API returned zero
    if (distanceKm == 0) {
      distanceKm = MapUtils.haversineKm(pickupPoint!, destinationPoint!);
    }
    if (durationMin == 0) durationMin = distanceKm * 2.5;

    if (mounted) setState(() => isLoadingRoute = false);

    // Fit camera after route loads
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || _mapController == null) return;
      MapUtils.fitBounds(_mapController!, routePoints, padding: 60);
    });
  }

  // ── Metric tile (distance / duration / fast route) ──────────────────────
  Widget _buildMetricTile(
    _C c, {
    required IconData icon,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: c.cardSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: c.green),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 12,
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Route preview card ───────────────────────────────────────────────────
  Widget _buildRoutePreview(_C c) {
    return GlassCard(
      borderRadius: BorderRadius.circular(28),
      color: c.card,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('routePreview'),
              style: AppTextStyles.heading.copyWith(
                fontSize: 18,
                color: c.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                _buildMetricTile(
                  c,
                  icon: Icons.location_on_outlined,
                  label: isLoadingRoute
                      ? context.tr('loading')
                      : '${distanceKm.toStringAsFixed(1)} km',
                ),
                const SizedBox(width: 8),
                _buildMetricTile(
                  c,
                  icon: Icons.access_time,
                  label: isLoadingRoute
                      ? context.tr('loading')
                      : '${durationMin.toStringAsFixed(0)} ${context.tr('mins')}',
                ),
                const SizedBox(width: 8),
                _buildMetricTile(
                  c,
                  icon: Icons.alt_route,
                  label: context.tr('fastRoute'),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Container(
              height: 160,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: isLoadingRoute
                  ? Center(child: CircularProgressIndicator(color: c.green))
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: GoogleMap(
                            onMapCreated:
                                (GoogleMapController controller) async {
                                  _mapController = controller;
                                  final points = routePoints.isNotEmpty
                                      ? routePoints
                                      : [pickupPoint!, destinationPoint!];

                                  double minLat = points.first.latitude;
                                  double maxLat = points.first.latitude;
                                  double minLng = points.first.longitude;
                                  double maxLng = points.first.longitude;

                                  for (final p in points) {
                                    if (p.latitude < minLat) {
                                      minLat = p.latitude;
                                    }
                                    if (p.latitude > maxLat) {
                                      maxLat = p.latitude;
                                    }
                                    if (p.longitude < minLng) {
                                      minLng = p.longitude;
                                    }
                                    if (p.longitude > maxLng) {
                                      maxLng = p.longitude;
                                    }
                                  }

                                  final southWest = LatLng(minLat, minLng);
                                  final northEast = LatLng(maxLat, maxLng);
                                  final bounds = LatLngBounds(
                                    southwest: southWest,
                                    northeast: northEast,
                                  );

                                  await _mapController!.moveCamera(
                                    CameraUpdate.newLatLngBounds(bounds, 60),
                                  );
                                },
                            initialCameraPosition: CameraPosition(
                              target: pickupPoint!,
                              zoom: 13,
                            ),
                            mapType: MapType.normal,
                            polylines: {
                              Polyline(
                                polylineId: const PolylineId('route'),
                                points: routePoints,
                                color: c.green,
                                width: 6,
                              ),
                            },
                            markers: {
                              Marker(
                                markerId: const MarkerId('pickup'),
                                position: pickupPoint!,
                                infoWindow: InfoWindow(title: widget.pickup),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueBlue,
                                ),
                              ),
                              Marker(
                                markerId: const MarkerId('destination'),
                                position: destinationPoint!,
                                infoWindow: InfoWindow(
                                  title: widget.destination,
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueRed,
                                ),
                              ),
                            },
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            gestureRecognizers:
                                <Factory<OneSequenceGestureRecognizer>>{
                                  Factory<OneSequenceGestureRecognizer>(
                                    () => EagerGestureRecognizer(),
                                  ),
                                },
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (_mapController != null) {
                                    _mapController!.animateCamera(
                                      CameraUpdate.zoomIn(),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(220),
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    color: c.green,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () {
                                  if (_mapController != null) {
                                    _mapController!.animateCamera(
                                      CameraUpdate.zoomOut(),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(220),
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    color: c.green,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 6),

            // pickup / destination box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.cardSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.pickup,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.destination,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Individual ride card ─────────────────────────────────────────────────
  Widget _buildRideCard(
    _C c,
    Map<String, dynamic> ride,
    bool isSelected,
    int index,
  ) {
    return GestureDetector(
      onTap: () => setState(() {
        _selected = index;
      }),
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        color: isSelected ? c.green.withAlpha((0.14 * 255).round()) : c.card,
        border: Border.all(
          color: isSelected ? c.green : c.border,
          width: isSelected ? 1.6 : 1,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // icon/image box
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isSelected
                      ? c.green.withAlpha((0.15 * 255).round())
                      : c.iconBoxBg,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: c.green, width: 1.5)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CategoryVehicleImage(
                    vehicleType:
                        ride['category']?.toString() ??
                        ride['vehicleType']?.toString() ??
                        ride['name']?.toString() ??
                        '',
                    size: 52,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ride name
                    Text(
                      ride['name'],
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 16,
                        color: c.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 2),

                    // detail
                    Text(
                      _localizedRideDetail(ride['detail']?.toString()),
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // "Discuss price with driver"
                  Text(
                    context.tr('discussPriceWithDriver'),
                    textAlign: TextAlign.right,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 11,
                      color: c.dark ? c.yellow : AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 2),

                  // ETA
                  if (ride['eta'] != null && ride['eta'].toString().isNotEmpty)
                    Text(
                      _formatEta(ride['eta']?.toString()),
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        color: c.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Confirm ride logic ───────────────────────────────────────────────────

  Future<void> _confirmRide(BuildContext context) async {
    if (_isSearching) return;

    setState(() {
      _isSearching = true;
      _driverFound = false;
    });

    final navigator = Navigator.of(context);

    // ── Step 1: get userId from session ──────────────────────────────────
    final userId = await SessionService.getUserId() ?? 'guest_user';

    final selectedRide = _filteredRides[_selected];
    final vehicleTypeKey = _mapRideTypeToEnum(selectedRide['name']);
    final distanceStr = '${distanceKm.toStringAsFixed(1)} km';
    final durationStr = '${durationMin.toStringAsFixed(0)} mins';

    debugPrint(
      '[RIDE_FLOW] Creating ride request on backend for broadcasting...',
    );
    final res = await ApiService.requestRide(
      userId: userId,
      pickupLocation: widget.pickup,
      dropoffLocation: widget.destination,
      rideType: vehicleTypeKey,
      pickupLat: pickupPoint?.latitude,
      pickupLng: pickupPoint?.longitude,
      destinationLat: destinationPoint?.latitude,
      destinationLng: destinationPoint?.longitude,
      distance: distanceStr,
      duration: durationStr,
      distanceKm: distanceKm,
      durationMin: durationMin,
    );

    String rideId = 'ride_${DateTime.now().millisecondsSinceEpoch}';
    if (res.success) {
      final data = res.data;
      final nested = data['ride'] as Map?;
      rideId =
          data['_id']?.toString() ??
          data['rideId']?.toString() ??
          data['id']?.toString() ??
          nested?['_id']?.toString() ??
          nested?['rideId']?.toString() ??
          nested?['id']?.toString() ??
          rideId;
      debugPrint('[RIDE_FLOW] Created ride successfully: rideId=$rideId');
    } else {
      debugPrint(
        '[RIDE_FLOW] Failed to create ride request: ${res.errorMessage}',
      );
    }

    if (!mounted) return;
    setState(() {
      _driverFound = true;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() {
      _isSearching = false;
      _driverFound = false;
    });

    // DriversListScreen fetches drivers itself using the real pickup coordinates
    final result = await navigator.push<dynamic>(
      MaterialPageRoute(
        builder: (_) => DriversListScreen(
          rideType: selectedRide['name'],
          pickup: widget.pickup,
          destination: widget.destination,
          rideId: rideId,
          pickupLat: pickupPoint?.latitude ?? 28.6139,
          pickupLng: pickupPoint?.longitude ?? 77.2090,
          distanceKm: distanceKm,
          durationMin: durationMin,
        ),
      ),
    );

    if (result == 'retry' && mounted) {
      _confirmRide(context);
    }

    debugPrint(
      '📢 [RIDE_TYPE_DEBUG] Selected ride name: ${selectedRide['name']}',
    );
    debugPrint(
      '📢 [RIDE_TYPE_DEBUG] Selected ride rideType: ${selectedRide['rideType']}',
    );
    debugPrint(
      '📢 [RIDE_TYPE_DEBUG] Selected ride vehicleType: ${selectedRide['vehicleType']}',
    );
  }

  // ── Searching overlay ────────────────────────────────────────────────────
  Widget _buildSearchingOverlay(_C c) {
    return IgnorePointer(
      ignoring: !_isSearching,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: _isSearching ? 1 : 0,
        child: Container(
          color: Colors.black.withAlpha((0.45 * 255).round()),
          child: Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.overlayCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  lottie.Lottie.asset(
                    'assets/animations/ride_search.json',
                    width: 140,
                    height: 140,
                    repeat: !_driverFound,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _driverFound
                        ? context.tr('driverFound')
                        : context.tr('searchingDriver'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 18,
                      color: c.overlayText,
                    ),
                  ),
                ],
              ),
            ).animate().fade(),
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _C(isDark);

    return Scaffold(
      backgroundColor: c.scaffold,

      appBar: AppBar(
        backgroundColor: c.appBar,
        elevation: 0,
        foregroundColor: c.appBarTitle,
        iconTheme: IconThemeData(color: c.appBarTitle),
        title: Text(
          context.tr('chooseYourRide'),
          style: TextStyle(
            color: c.appBarTitle,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),

      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),

                  _buildRoutePreview(c),

                  const SizedBox(height: 4),

                  Text(
                    context.tr('availableRides'),
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 18,
                      color: c.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  if (_loadingCategories && _filteredRides.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: c.green,
                        ),
                      ),
                    )
                  else if (_filteredRides.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No available rides found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _filteredRides.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final ride = _filteredRides[index];
                        return _buildRideCard(c, ride, _selected == index, index);
                      },
                    ),
                ],
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: CustomButton(
                label: context.tr('confirmRide'),
                color: AppColors.secondary,
                onPressed: () => _confirmRide(context),
              ),
            ),

            if (_isSearching) _buildSearchingOverlay(c),
          ],
        ),
      ),
    );
  }
}
