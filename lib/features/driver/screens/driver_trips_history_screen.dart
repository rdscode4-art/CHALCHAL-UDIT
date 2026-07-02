import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import 'trip_details_screen.dart';
import '../../../core/localization/app_localizations.dart';

class DriverTripsHistoryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> tripHistory;

  const DriverTripsHistoryScreen({super.key, required this.tripHistory});

  @override
  State<DriverTripsHistoryScreen> createState() =>
      _DriverTripsHistoryScreenState();
}

class _DriverTripsHistoryScreenState extends State<DriverTripsHistoryScreen> {
  String _searchQuery = '';
  String _selectedRideType = 'All';
  String _selectedDateOption = 'All Time';
  DateTimeRange? _customDateRange;
  String _selectedFareOption = 'All';
  String _sortBy = 'Newest';

  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _dynamicTripHistory = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dynamicTripHistory = List.from(widget.tripHistory);
    _fetchTripHistoryFromBackend();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTripHistoryFromBackend() async {
    if (mounted) {
      setState(() {
        _isLoading = _dynamicTripHistory.isEmpty;
        _errorMessage = null;
      });
    }

    try {
      final driverId = await SessionService.getDriverId();
      if (driverId == null || driverId.isEmpty || driverId == 'mock') {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final results = await Future.wait([
        ApiService.getDriverDashboard(driverId),
        ApiService.getDriverRides(driverId),
      ]);

      final dashboardRes = results[0];
      final ridesRes = results[1];

      final List<Map<String, dynamic>> parsedHistory = [];
      final session = await SessionService.getSession();
      final vehicleType = session['vehicleType'] ?? 'Auto';

      void parseAndAddRide(dynamic item) {
        if (item is Map<String, dynamic>) {
          final normalized = ApiService.normalizeDriverRidePayload(
            item,
            fallbackDriverId: driverId,
          );

          final pickup = normalized['pickup']?.toString() ?? 'Pickup';
          final dest = normalized['destination']?.toString() ?? 'Destination';
          final rType = normalized['rideType']?.toString() ?? vehicleType;

          var distStr = '—';
          final rawDistance =
              normalized['distance'] ??
              normalized['distanceKm'] ??
              normalized['distance_km'];
          if (rawDistance != null) {
            distStr = rawDistance.toString().trim();
            if (!distStr.toLowerCase().contains('km') &&
                double.tryParse(distStr) != null) {
              distStr = '$distStr km';
            }
          }

          var durStr = '—';
          final rawDuration =
              normalized['duration'] ??
              normalized['durationMin'] ??
              normalized['duration_min'] ??
              normalized['durationMins'];
          if (rawDuration != null) {
            durStr = rawDuration.toString().trim();
            if (!durStr.toLowerCase().contains('min') &&
                int.tryParse(durStr) != null) {
              durStr = '$durStr mins';
            }
          }

          var dateStr = '—';
          var timeStr = '—';
          if (normalized['date'] != null &&
              normalized['date'].toString().trim().isNotEmpty) {
            dateStr = normalized['date'].toString().trim();
          }
          if (normalized['time'] != null &&
              normalized['time'].toString().trim().isNotEmpty) {
            timeStr = normalized['time'].toString().trim();
          }

          final dateIsoStr =
              normalized['completedAt']?.toString() ??
              normalized['startedAt']?.toString() ??
              normalized['createdAt']?.toString();

          if ((dateStr == '—' || timeStr == '—') &&
              dateIsoStr != null &&
              dateIsoStr.trim().isNotEmpty) {
            try {
              final parsedDate = DateTime.parse(dateIsoStr.trim()).toLocal();
              if (dateStr == '—') {
                dateStr = _formatDate(parsedDate);
              }
              if (timeStr == '—') {
                timeStr = _formatTime(parsedDate);
              }
            } catch (_) {}
          }

          // KB START HUA KB END HUA (local timezone representation)
          var startTime = '—';
          if (normalized['startTime'] != null &&
              normalized['startTime'].toString().trim().isNotEmpty) {
            startTime = normalized['startTime'].toString().trim();
          } else if (normalized['startedAt'] != null &&
              normalized['startedAt'].toString().trim().isNotEmpty) {
            try {
              final parsedStart = DateTime.parse(
                normalized['startedAt'].toString().trim(),
              ).toLocal();
              startTime = _formatTime(parsedStart);
            } catch (_) {}
          }
          if (startTime == '—') {
            startTime = timeStr; // fallback to time string from creation
          }

          var endTime = '—';
          if (normalized['endTime'] != null &&
              normalized['endTime'].toString().trim().isNotEmpty) {
            endTime = normalized['endTime'].toString().trim();
          } else if (normalized['completedAt'] != null &&
              normalized['completedAt'].toString().trim().isNotEmpty) {
            try {
              final parsedEnd = DateTime.parse(
                normalized['completedAt'].toString().trim(),
              ).toLocal();
              endTime = _formatTime(parsedEnd);
            } catch (_) {}
          }

          // Extract passenger name and phone (handles both flat keys and nested objects)
          String riderName = '';
          String riderPhone = '—';

          final userMap = (normalized['user'] is Map)
              ? normalized['user']
              : ((normalized['rider'] is Map)
                    ? normalized['rider']
                    : ((normalized['passenger'] is Map)
                          ? normalized['passenger']
                          : normalized['userId']));
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
            if (fallbackName.trim().isNotEmpty) {
              riderName = fallbackName;
            } else {
              riderName = 'Passenger';
            }
          }

          if (riderPhone == '—' || riderPhone.trim().isEmpty) {
            final fallbackPhone =
                normalized['riderPhone']?.toString() ??
                normalized['passengerPhone']?.toString() ??
                normalized['userPhone']?.toString() ??
                normalized['phone']?.toString() ??
                '—';
            riderPhone = fallbackPhone;
          }

          final idStr =
              normalized['rideId']?.toString() ??
              normalized['_id']?.toString() ??
              normalized['id']?.toString() ??
              '';

          if (parsedHistory.any(
            (element) => element['id'] == idStr && idStr.isNotEmpty,
          )) {
            return;
          }

          final status =
              normalized['status']?.toString().toLowerCase() ?? 'completed';

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

      if (ridesRes.success) {
        final ridesList = ridesRes.data['rides'] as List<dynamic>? ?? [];
        for (var item in ridesList) {
          parseAndAddRide(item);
        }
      }

      if (dashboardRes.success) {
        final historyList =
            dashboardRes.data['tripHistory'] as List<dynamic>? ?? [];
        for (var item in historyList) {
          parseAndAddRide(item);
        }
      }

      // Show initial list quickly, then enrich from individual ride fetches
      if (mounted) {
        setState(() {
          _dynamicTripHistory = parsedHistory;
          _isLoading = false;
        });
      }

      // Enrich trips where fare or passenger name is missing by fetching each ride individually
      await _enrichTripsFromRideIds(parsedHistory);
    } catch (e) {
      debugPrint('Error fetching trip history: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load trip history from server.';
        });
      }
    }
  }

  /// Fetches individual ride details for trips that are missing fare or passenger name.
  /// This is needed because bulk API responses often omit populated user/fare fields.
  Future<void> _enrichTripsFromRideIds(List<Map<String, dynamic>> trips) async {
    final toEnrich = trips.where((t) {
      final fare = t['fare']?.toString() ?? '—';
      final name = t['riderName']?.toString() ?? '';
      final rideId = t['rideId']?.toString() ?? '';
      // Enrich if fare is missing/zero or passenger name is generic/empty
      return rideId.isNotEmpty &&
          !rideId.startsWith('ride_') &&
          (fare == '—' ||
              fare == '0' ||
              fare.isEmpty ||
              name == 'Passenger' ||
              name.isEmpty);
    }).toList();

    if (toEnrich.isEmpty) return;
    debugPrint(
      '[History] Enriching ${toEnrich.length} trips from individual ride API...',
    );

    bool didUpdate = false;

    for (final trip in toEnrich) {
      final rideId = trip['rideId']!.toString();
      try {
        final res = await ApiService.getRide(rideId);
        if (!res.success) continue;

        final rideData = res.data;

        // Extract fare from the populated ride document
        final rawFare =
            rideData['fare'] ??
            rideData['finalFare'] ??
            rideData['price'] ??
            rideData['estimatedFare'];
        if (rawFare != null) {
          final fareStr = rawFare.toString().replaceAll(RegExp(r'[^0-9.]'), '');
          if (fareStr.isNotEmpty && fareStr != '0') {
            trip['fare'] = fareStr;
            didUpdate = true;
            debugPrint('[History] Ride $rideId — fare enriched: ₹$fareStr');
          }
        }

        // Extract passenger name from the populated user/rider object
        String enrichedName = '';
        String enrichedPhone = '—';
        final userObj =
            rideData['user'] ?? rideData['rider'] ?? rideData['passenger'];
        if (userObj is Map<String, dynamic>) {
          enrichedName =
              userObj['name']?.toString() ??
              userObj['userName']?.toString() ??
              userObj['passengerName']?.toString() ??
              '';
          enrichedPhone =
              userObj['phone']?.toString() ??
              userObj['userPhone']?.toString() ??
              '—';
        }
        if (enrichedName.isEmpty) {
          enrichedName =
              rideData['riderName']?.toString() ??
              rideData['passengerName']?.toString() ??
              rideData['userName']?.toString() ??
              '';
        }
        if (enrichedPhone == '—') {
          enrichedPhone =
              rideData['riderPhone']?.toString() ??
              rideData['passengerPhone']?.toString() ??
              rideData['phone']?.toString() ??
              '—';
        }

        if (enrichedName.isNotEmpty && enrichedName != 'Passenger') {
          trip['riderName'] = enrichedName;
          trip['passengerName'] = enrichedName;
          if (enrichedPhone != '—') {
            trip['passengerPhone'] = enrichedPhone;
          }
          didUpdate = true;
          debugPrint(
            '[History] Ride $rideId — passenger enriched: $enrichedName',
          );
        }

        // Also enrich distance/duration if missing
        if (trip['distance'] == '—') {
          final rawDist =
              rideData['distance'] ??
              rideData['distanceKm'] ??
              rideData['distance_km'];
          if (rawDist != null) {
            var distStr = rawDist.toString().trim();
            if (!distStr.toLowerCase().contains('km') &&
                double.tryParse(distStr) != null) {
              distStr = '$distStr km';
            }
            trip['distance'] = distStr;
            didUpdate = true;
          }
        }
      } catch (e) {
        debugPrint('[History] Failed to enrich ride $rideId: $e');
      }
    }

    if (didUpdate && mounted) {
      setState(() {
        _dynamicTripHistory = List.from(trips);
      });
      debugPrint('[History] Trip list enriched and UI updated.');
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  List<String> get _rideTypes {
    final types = _dynamicTripHistory
        .map((t) => t['rideType'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    types.sort();
    return ['All', ...types];
  }

  DateTime? _parseTripDate(Map<String, dynamic> trip) {
    final createdAtStr = trip['createdAt'] as String?;
    if (createdAtStr != null && createdAtStr.isNotEmpty) {
      try {
        return DateTime.parse(createdAtStr);
      } catch (_) {}
    }

    final dateStr = trip['date'] as String?;
    if (dateStr != null && dateStr.isNotEmpty && dateStr != '—') {
      try {
        final parts = dateStr.trim().split(RegExp(r'\s+'));
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final monthStr = parts[1].toLowerCase().substring(0, 3);
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
    }
    return null;
  }

  double _parseFare(Map<String, dynamic> trip) {
    final fareStr = trip['fare'] as String?;
    if (fareStr == null || fareStr.isEmpty || fareStr == '—') return 0.0;
    final cleanStr = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? 0.0;
  }

  double _parseDistance(Map<String, dynamic> trip) {
    final distStr = trip['distance'] as String?;
    if (distStr == null || distStr.isEmpty || distStr == '—') return 0.0;
    final cleanStr = distStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? 0.0;
  }

  String _formatDisplayFare(String fareStr) {
    if (fareStr == '—' || fareStr.isEmpty) return '—';
    final clean = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return '₹$clean';
  }

  List<Map<String, dynamic>> get _filteredAndSortedTrips {
    List<Map<String, dynamic>> results = List.from(_dynamicTripHistory);

    // 1. Search Query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      results = results.where((t) {
        final rider = (t['riderName'] ?? t['passengerName'] ?? '')
            .toString()
            .toLowerCase();
        final pickup = (t['pickup'] ?? '').toString().toLowerCase();
        final destination = (t['destination'] ?? '').toString().toLowerCase();
        final rideId = (t['id'] ?? t['rideId'] ?? '').toString().toLowerCase();
        return rider.contains(query) ||
            pickup.contains(query) ||
            destination.contains(query) ||
            rideId.contains(query);
      }).toList();
    }

    // 2. Ride Type Filter
    if (_selectedRideType != 'All') {
      results = results
          .where((t) => t['rideType'] == _selectedRideType)
          .toList();
    }

    // 3. Date Filter
    if (_selectedDateOption != 'All Time') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      results = results.where((t) {
        final dt = _parseTripDate(t);
        if (dt == null) return false;

        final tripDay = DateTime(dt.year, dt.month, dt.day);

        switch (_selectedDateOption) {
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
            if (_customDateRange == null) return true;
            final start = DateTime(
              _customDateRange!.start.year,
              _customDateRange!.start.month,
              _customDateRange!.start.day,
            );
            final end = DateTime(
              _customDateRange!.end.year,
              _customDateRange!.end.month,
              _customDateRange!.end.day,
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
    if (_selectedFareOption != 'All') {
      results = results.where((t) {
        final fare = _parseFare(t);
        switch (_selectedFareOption) {
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
      switch (_sortBy) {
        case 'Oldest':
          final dtA = _parseTripDate(a) ?? DateTime(1970);
          final dtB = _parseTripDate(b) ?? DateTime(1970);
          return dtA.compareTo(dtB);

        case 'Fare: High to Low':
          return _parseFare(b).compareTo(_parseFare(a));

        case 'Fare: Low to High':
          return _parseFare(a).compareTo(_parseFare(b));

        case 'Distance: Longest':
          return _parseDistance(b).compareTo(_parseDistance(a));

        case 'Newest':
        default:
          final dtA = _parseTripDate(a) ?? DateTime(1970);
          final dtB = _parseTripDate(b) ?? DateTime(1970);
          return dtB.compareTo(dtA);
      }
    });

    return results;
  }

  int _getActiveFiltersCount() {
    int count = 0;
    if (_sortBy != 'Newest') count++;
    if (_selectedRideType != 'All') count++;
    if (_selectedDateOption != 'All Time') count++;
    if (_selectedFareOption != 'All') count++;
    return count;
  }

  void _resetAllFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _sortBy = 'Newest';
      _selectedRideType = 'All';
      _selectedDateOption = 'All Time';
      _customDateRange = null;
      _selectedFareOption = 'All';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final cardSoft = isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final textSec = isDark ? AppColors.textLight : AppColors.textGrey;
    final green = AppColors.secondary;

    final tripsToShow = _filteredAndSortedTrips;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(context.tr('tripHistory')),
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: textPri,
      ),
      body: Column(
        children: [
          _buildSearchHeader(
            context,
            surface,
            cardSoft,
            border,
            textPri,
            textSec,
            green,
          ),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.accentRed.withAlpha(20),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.accentRed,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(green),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchTripHistoryFromBackend,
                    color: green,
                    child: tripsToShow.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
                                child: _buildEmptyState(textSec, border, green),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: tripsToShow.length,
                            itemBuilder: (context, index) {
                              final trip = tripsToShow[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TripDetailsScreen(trip: trip),
                                    ),
                                  );
                                },
                                child: _buildTripCard(
                                  trip,
                                  surface,
                                  cardSoft,
                                  border,
                                  textPri,
                                  textSec,
                                  green,
                                  isDark,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(
    BuildContext context,
    Color surface,
    Color cardSoft,
    Color border,
    Color textPri,
    Color textSec,
    Color green,
  ) {
    final activeFiltersCount = _getActiveFiltersCount();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: surface,
      child: Column(
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
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    style: TextStyle(color: textPri, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: context.tr('searchHistoryPlaceholder'),
                      hintStyle: TextStyle(color: textSec, fontSize: 13),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: textSec,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
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
                onTap: _showFiltersBottomSheet,
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
                _buildFilterPill(
                  icon: Icons.swap_vert_rounded,
                  label: 'Sort: $_sortBy',
                  isActive: _sortBy != 'Newest',
                  onTap: _showFiltersBottomSheet,
                  green: green,
                  border: border,
                  cardSoft: cardSoft,
                  textSec: textSec,
                  textPri: textPri,
                ),
                const SizedBox(width: 8),
                _buildFilterPill(
                  icon: Icons.directions_car_outlined,
                  label: _selectedRideType == 'All'
                      ? 'Ride Type'
                      : _selectedRideType,
                  isActive: _selectedRideType != 'All',
                  onTap: _showFiltersBottomSheet,
                  green: green,
                  border: border,
                  cardSoft: cardSoft,
                  textSec: textSec,
                  textPri: textPri,
                ),
                const SizedBox(width: 8),
                _buildFilterPill(
                  icon: Icons.date_range_outlined,
                  label:
                      _selectedDateOption == 'Custom' &&
                          _customDateRange != null
                      ? '${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}'
                      : _selectedDateOption == 'All Time'
                      ? 'Date'
                      : _selectedDateOption,
                  isActive: _selectedDateOption != 'All Time',
                  onTap: _showFiltersBottomSheet,
                  green: green,
                  border: border,
                  cardSoft: cardSoft,
                  textSec: textSec,
                  textPri: textPri,
                ),
                const SizedBox(width: 8),
                _buildFilterPill(
                  icon: Icons.payments_outlined,
                  label: _selectedFareOption == 'All'
                      ? 'Fare'
                      : _selectedFareOption,
                  isActive: _selectedFareOption != 'All',
                  onTap: _showFiltersBottomSheet,
                  green: green,
                  border: border,
                  cardSoft: cardSoft,
                  textSec: textSec,
                  textPri: textPri,
                ),
                if (activeFiltersCount > 0 || _searchQuery.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _resetAllFilters,
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
      ),
    );
  }

  Widget _buildFilterPill({
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

  Widget _buildEmptyState(Color textSec, Color border, Color green) {
    final hasActiveFilters =
        _getActiveFiltersCount() > 0 || _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasActiveFilters ? Icons.search_off_rounded : Icons.history,
              size: 64,
              color: border,
            ),
            const SizedBox(height: 16),
            Text(
              hasActiveFilters
                  ? context.tr('noMatchingTrips')
                  : context.tr('noTripsYet'),
              style: AppTextStyles.body.copyWith(
                color: textSec,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasActiveFilters
                  ? context.tr('adjustFilters')
                  : context.tr('completeRideToSeeHistory'),
              style: AppTextStyles.body.copyWith(
                color: textSec.withAlpha(180),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _resetAllFilters,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(context.tr('resetAllFilters')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFiltersBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final green = AppColors.secondary;

    String localSortBy = _sortBy;
    String localRideType = _selectedRideType;
    String localDateOption = _selectedDateOption;
    DateTimeRange? localCustomDateRange = _customDateRange;
    String localFareOption = _selectedFareOption;

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
                          context.tr('filterAndSort'),
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
                              context.tr('resetAll'),
                              style: const TextStyle(
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
                      context.tr('sortBy'),
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
                      children: _rideTypes.map((type) {
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
                            _sortBy = localSortBy;
                            _selectedRideType = localRideType;
                            _selectedDateOption = localDateOption;
                            _customDateRange = localCustomDateRange;
                            _selectedFareOption = localFareOption;
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

  Widget _buildTripCard(
    Map<String, dynamic> trip,
    Color surface,
    Color cardSoft,
    Color border,
    Color textPri,
    Color textSec,
    Color green,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ride Completed',
                    style: AppTextStyles.body.copyWith(
                      fontSize: 11,
                      color: textSec,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trip['date'] as String? ?? '—',
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPri,
                    ),
                  ),
                ],
              ),
              if ((trip['rideId'] as String? ?? trip['id'] as String? ?? '')
                  .isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: border.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ID: ${(trip['rideId'] as String? ?? trip['id'] as String? ?? '').substring(0, (trip['rideId'] as String? ?? trip['id'] as String? ?? '').length > 8 ? 8 : (trip['rideId'] as String? ?? trip['id'] as String? ?? '').length)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: textSec,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surface.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border.withAlpha(60)),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_outlined, size: 14, color: green),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Started',
                            style: TextStyle(fontSize: 9, color: textSec),
                          ),
                          Text(
                            trip['startTime'] as String? ?? '—',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textPri,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 14, color: textSec),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ended',
                            style: TextStyle(fontSize: 9, color: textSec),
                          ),
                          Text(
                            trip['endTime'] as String? ?? '—',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textPri,
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surface.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border.withAlpha(60)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: textSec),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Passenger',
                        style: TextStyle(fontSize: 10, color: textSec),
                      ),
                      Text(
                        (trip['passengerName']?.toString() ?? '')
                                .trim()
                                .isNotEmpty
                            ? (trip['passengerName']!.toString())
                            : ((trip['riderName']?.toString() ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? (trip['riderName']!.toString())
                                  : 'Passenger'),
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPri,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From',
                      style: TextStyle(fontSize: 10, color: textSec),
                    ),
                    Text(
                      trip['pickup'] as String? ?? '—',
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        color: textPri,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on, size: 14, color: AppColors.accentRed),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To', style: TextStyle(fontSize: 10, color: textSec)),
                    Text(
                      trip['destination'] as String? ?? '—',
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        color: textPri,
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
          Row(
            children: [
              Expanded(
                child: _buildMetric(
                  Icons.straighten,
                  'Distance',
                  trip['distance'] as String? ?? '—',
                  textPri,
                  textSec,
                  border,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRideTypeMetric(
                  trip['rideType'] as String? ?? '—',
                  textPri,
                  textSec,
                  border,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: green.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: green.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fare',
                        style: TextStyle(fontSize: 10, color: textSec),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDisplayFare(trip['fare'] as String? ?? '—'),
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if ((trip['rating'] as String? ?? '—') != '—') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.accentYellow.withAlpha(60),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rating',
                          style: TextStyle(fontSize: 10, color: textSec),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.accentYellow,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              trip['rating'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accentYellow,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    IconData icon,
    String label,
    String value,
    Color textPri,
    Color textSec,
    Color border,
  ) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
      color: border.withAlpha(15),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.secondary),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textPri,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: textSec)),
      ],
    ),
  );

  /// Like [_buildMetric] but uses [CategoryVehicleImage] instead of an icon.
  Widget _buildRideTypeMetric(
    String rideType,
    Color textPri,
    Color textSec,
    Color border,
  ) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
      color: border.withAlpha(15),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryVehicleImage(vehicleType: rideType, size: 20),
        const SizedBox(height: 4),
        Text(
          rideType == '—' ? '—' : rideType,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textPri,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text('Type', style: TextStyle(fontSize: 9, color: textSec)),
      ],
    ),
  );
}
