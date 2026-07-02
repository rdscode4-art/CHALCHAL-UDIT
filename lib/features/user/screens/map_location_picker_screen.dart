import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/widgets/custom_button.dart';

class MapLocationPickerScreen extends StatefulWidget {
  final String title;

  const MapLocationPickerScreen({super.key, required this.title});

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  GoogleMapController? _mapController;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    // Ensure map is ready before using controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _mapReady = true;
        });
        // Auto-select and pin the current location when the screen opens
        // so the booking flow shows a readable address instead of raw coords.
        _selectCurrentLocation();
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  bool get _supportsMap {
    final key = AppConstants.googlePlacesApiKey;
    final validKey = key.isNotEmpty && !key.startsWith('YOUR_');
    return validKey &&
        (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  LatLng _selectedPosition = const LatLng(28.6139, 77.2090);
  LatLng? _currentLocationPosition;
  LatLng? _destinationPosition;
  List<LatLng> _routePoints = [];
  String _selectedLabel = 'Tap on the map to choose a location';
  bool _useCurrentLocation = false;
  bool _isFetchingLocation = false;

  final List<String> _fallbackLocations = [
    'City Center',
    'Airport Terminal',
    'Station Square',
    'Mall Avenue',
  ];
  int _fallbackIndex = 0;

  String get _displayLabel {
    if (_isFetchingLocation) {
      return 'Resolving address...';
    }
    if (_useCurrentLocation) {
      return _selectedLabel;
    }
    return _supportsMap ? _selectedLabel : _fallbackLocations[_fallbackIndex];
  }

  Future<void> _onMapTap(LatLng position) async {
    setState(() {
      _useCurrentLocation = false;
      _selectedPosition = position;
      _isFetchingLocation = true;
      _selectedLabel = 'Resolving address...';
    });

    final address = await _fetchAddressFromCoordinates(position);
    if (mounted) {
      setState(() {
        _selectedLabel = address;
        _isFetchingLocation = false;
      });
    }
  }

  /// Set route points for polyline rendering
  void setRoutePoints(List<LatLng> points) {
    setState(() {
      _routePoints = points;
    });
  }

  /// Set current location marker
  void setCurrentLocation(LatLng location) {
    setState(() {
      _currentLocationPosition = location;
    });
  }

  /// Set destination marker
  void setDestination(LatLng location) {
    setState(() {
      _destinationPosition = location;
    });
  }

  void _selectFallbackLocation(int index) {
    setState(() {
      _useCurrentLocation = false;
      _fallbackIndex = index;
      _selectedLabel = _fallbackLocations[index];
    });
  }

  Future<void> _selectCurrentLocation() async {
    if (!_supportsMap) {
      setState(() {
        _useCurrentLocation = true;
        _selectedLabel = 'Current location';
      });
      return;
    }

    setState(() {
      _isFetchingLocation = true;
      _useCurrentLocation = false;
    });

    final position = await _getCurrentPosition();
    if (position == null) {
      setState(() {
        _isFetchingLocation = false;
      });
      _showMessage(
        'Unable to access current location. Please enable location permissions.',
      );
      return;
    }

    final selectedLatLng = LatLng(position.latitude, position.longitude);
    final label = await _fetchAddressFromCoordinates(selectedLatLng);

    setState(() {
      _useCurrentLocation = true;
      _selectedPosition = selectedLatLng;
      _currentLocationPosition = selectedLatLng;
      _selectedLabel = label;
      _isFetchingLocation = false;
    });

    // Only move map if controller is ready
    if (_mapReady && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(selectedLatLng, 16),
      );
    }
  }

  Future<Position?> _getCurrentPosition() async {
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
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocode [latLng] to a human-readable address string.
  ///
  /// Delegates to [GeocodingService] which tries:
  ///   1. Device-native geocoding package (no API key needed)
  ///   2. Google Geocoding HTTP API
  ///   3. Falls back to a readable "lat, lng" string as last resort.
  Future<String> _fetchAddressFromCoordinates(LatLng latLng) async {
    final resolved = await GeocodingService.reverseGeocode(latLng);
    if (resolved != null && resolved.isNotEmpty) return resolved;

    // ── Readable coordinate fallback (last resort) ────────────────────────
    return '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.35; // Map takes 35% of screen
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.darkBackground
        : AppColors.background;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final surfaceSoftColor = isDark
        ? AppColors.darkSurfaceSoft
        : AppColors.surfaceSoft;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final onSurfaceColor = isDark
        ? AppColors.darkOnSurface
        : AppColors.textDark;
    final subduedTextColor = isDark
        ? AppColors.darkOnSurface.withAlpha(180)
        : AppColors.textGrey.withAlpha(180);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: AppTextStyles.heading.copyWith(
            fontSize: 20,
            color: onSurfaceColor,
          ),
        ),
        backgroundColor: surfaceColor,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurfaceColor),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Map widget with fixed height
            if (_supportsMap)
              SizedBox(
                height: mapHeight,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  child: GoogleMap(
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      // If we've already obtained the current location, center the map.
                      if (_currentLocationPosition != null) {
                        _mapController!.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            _currentLocationPosition!,
                            16,
                          ),
                        );
                      }
                    },
                    initialCameraPosition: CameraPosition(
                      target: _selectedPosition,
                      zoom: 15.0,
                    ),
                    mapType: MapType.normal,
                    onTap: _onMapTap,
                    polylines: {
                      if (_routePoints.isNotEmpty)
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _routePoints,
                          color: AppColors.accentStrong.withAlpha(180),
                          width: 5,
                          geodesic: true,
                        ),
                    },
                    markers: _buildMarkers(),
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
              ),
            if (!_supportsMap)
              SizedBox(
                height: mapHeight,
                child: Container(
                  color: surfaceSoftColor,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 72,
                        color: AppColors.accentStrong,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Map unavailable on this platform',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heading.copyWith(
                          fontSize: 16,
                          color: onSurfaceColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the suggested locations below instead.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: subduedTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Scrollable overlay UI with location selection
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: onSurfaceColor.withAlpha(12),
                        blurRadius: 22,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Selected location',
                              style: AppTextStyles.subtitle.copyWith(
                                fontSize: 14,
                                color: onSurfaceColor,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _selectCurrentLocation,
                            icon: const Icon(Icons.my_location, size: 18),
                            label: const Text('Current location'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.accentStrong,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          _displayLabel,
                          style: AppTextStyles.heading.copyWith(
                            fontSize: 16,
                            color: onSurfaceColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _supportsMap
                            ? 'Tap anywhere on the map to select your exact destination.'
                            : 'Choose one of the suggested fallback locations below.',
                        style: AppTextStyles.body.copyWith(
                          color: subduedTextColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_supportsMap) ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ChoiceChip(
                              label: const Text('Current location'),
                              selected: _useCurrentLocation,
                              selectedColor: AppColors.accentStrong.withAlpha(
                                25,
                              ),
                              backgroundColor: surfaceSoftColor,
                              labelStyle: TextStyle(color: onSurfaceColor),
                              onSelected: (_) => _selectCurrentLocation(),
                            ),
                            ..._fallbackLocations.asMap().entries.map((entry) {
                              final index = entry.key;
                              final location = entry.value;
                              final selected =
                                  !_useCurrentLocation &&
                                  index == _fallbackIndex;
                              return ChoiceChip(
                                label: Text(location),
                                selected: selected,
                                selectedColor: AppColors.accentStrong.withAlpha(
                                  25,
                                ),
                                backgroundColor: surfaceSoftColor,
                                labelStyle: TextStyle(color: onSurfaceColor),
                                onSelected: (_) =>
                                    _selectFallbackLocation(index),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      CustomButton(
                        label: 'Confirm location',
                        color: AppColors.accentStrong,
                        onPressed: () {
                          // Always return the resolved label (address when available),
                          // falling back to the suggested location text when maps are
                          // not supported.
                          Navigator.pop(
                            context,
                            _supportsMap
                                ? _selectedLabel
                                : _fallbackLocations[_fallbackIndex],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build markers for current location, pickup, and destination
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Selected/pickup marker (primary)
    markers.add(
      Marker(
        markerId: const MarkerId('selected'),
        position: _selectedPosition,
        infoWindow: InfoWindow(title: _selectedLabel),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
    );

    // Current location marker (if available)
    if (_currentLocationPosition != null &&
        _currentLocationPosition != _selectedPosition) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocationPosition!,
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    // Destination marker (if available)
    if (_destinationPosition != null &&
        _destinationPosition != _selectedPosition) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationPosition!,
          infoWindow: const InfoWindow(title: 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    return markers;
  }
}
