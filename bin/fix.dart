import 'dart:io';

void main() {
  final file = File('lib/features/driver/screens/driver_home_screen.dart');
  String c = file.readAsStringSync().replaceAll('\r\n', '\n');

  // 1
  c = c.replaceAll('String? _waitingForRideId;\n  Map<String, dynamic>? _waitingForRideData;', 'Map<String, Map<String, dynamic>> _waitingRides = {};');

  // 2
  final pushOld = r'''      if (_waitingForRideId == rideId) {
        debugPrint('🔔 FCM: Ride assigned to us! Clearing waiting state.');
        setState(() {
          _waitingForRideId = null;
          _waitingForRideData = null;
        });
      }''';
  final pushNew = r'''      if (_waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride assigned to us! Clearing waiting state.');
        setState(() {
          _waitingRides.remove(rideId);
        });
      }''';
  c = c.replaceAll(pushOld, pushNew);

  // 3
  final cancelOld = r'''    if (type == 'ride_cancelled' || event == 'cancelled') {
      final rideId = message.data['rideId']?.toString() ?? '';
      if (rideId.isNotEmpty && _waitingForRideId == rideId) {
        debugPrint('🔔 FCM: Ride cancelled by user. Clearing waiting state.');
        if (mounted) {
          setState(() {
            _waitingForRideId = null;
            _waitingForRideData = null;
          });
        }
      }
    }''';
  final cancelNew = r'''    if (type == 'ride_cancelled' || event == 'cancelled') {
      final rideId = message.data['rideId']?.toString() ?? '';
      if (rideId.isNotEmpty && _waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride cancelled by user. Clearing waiting state.');
        if (mounted) {
          setState(() {
            _waitingRides.remove(rideId);
          });
        }
      }
    }''';
  c = c.replaceAll(cancelOld, cancelNew);

  // 4
  final navOld = r'''              if (mounted) {
                setState(() {
                  _waitingForRideId = rideId;
                  _waitingForRideData = ride;
                });
              }''';
  final navNew = r'''              if (mounted) {
                setState(() {
                  _waitingRides[rideId] = ride;
                });
              }''';
  c = c.replaceAll(navOld, navNew);

  // 5
  final cancelInterestOld = r'''  void _cancelInterest() {
    if (_waitingForRideId == null) return;
    setState(() {
      _waitingForRideId = null;
      _waitingForRideData = null;
    });
  }''';
  final cancelInterestNew = r'''  void _cancelInterest(String rideId) {
    setState(() {
      _waitingRides.remove(rideId);
    });
  }''';
  c = c.replaceAll(cancelInterestOld, cancelInterestNew);

  // 6
  final bannerOld = r'''            if (_waitingForRideId != null && _waitingForRideData != null) ...[
              const SizedBox(height: 16),
              GlassCard(
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(16),
                color: AppColors.accentYellow.withAlpha(isDark ? 40 : 20),
                border: Border.all(
                  color: AppColors.accentYellow.withAlpha(120),
                  width: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.accentYellow,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Waiting for Passenger Confirmation...',
                            style: AppTextStyles.heading.copyWith(
                              fontSize: 16,
                              color: textPri,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ── Route ───────────────────────────────────────────────
                    Text(
                      'Pickup: ${_waitingForRideData!['pickup'] ?? 'Pickup'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: textSec,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Destination: ${_waitingForRideData!['destination'] ?? 'Destination'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: textSec,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Actions ─────────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                              color: green,
                            ),
                            label: Text(
                              'Chat with Passenger',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: green,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: green),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final userId = _waitingForRideData!['userId']?.toString() ??
                                           _waitingForRideData!['user_id']?.toString() ??
                                           '';
                              if (userId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: _waitingForRideId!,
                                      otherUserId: userId,
                                      otherUserName: _waitingForRideData!['userName']?.toString() ?? 'Passenger',
                                      otherUserRole: 'user',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.cancel_outlined,
                          size: 18,
                          color: AppColors.accentRed,
                        ),
                        label: const Text(
                          'Cancel Interest',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentRed,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppColors.accentRed),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _cancelInterest,
                      ),
                    ),
                  ],
                ),
              ),
            ],''';
  final bannerNew = r'''            ..._waitingRides.entries.map((entry) {
              final rideId = entry.key;
              final rideData = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: GlassCard(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(16),
                  color: AppColors.accentYellow.withAlpha(isDark ? 40 : 20),
                  border: Border.all(
                    color: AppColors.accentYellow.withAlpha(120),
                    width: 1.5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.accentYellow,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Waiting for Passenger Confirmation...',
                              style: AppTextStyles.heading.copyWith(
                                fontSize: 16,
                                color: textPri,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pickup: ${rideData['pickup'] ?? 'Pickup'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: textSec,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Destination: ${rideData['destination'] ?? 'Destination'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: textSec,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: green,
                              ),
                              label: Text(
                                'Chat with Passenger',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: green,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: green),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                final userId = rideData['userId']?.toString() ??
                                             rideData['user_id']?.toString() ??
                                             '';
                                if (userId.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        rideId: rideId,
                                        otherUserId: userId,
                                        otherUserName: rideData['userName']?.toString() ?? 'Passenger',
                                        otherUserRole: 'user',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.cancel_outlined,
                            size: 18,
                            color: AppColors.accentRed,
                          ),
                          label: const Text(
                            'Cancel Interest',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentRed,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppColors.accentRed),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _cancelInterest(rideId),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),''';
  c = c.replaceAll(bannerOld, bannerNew);

  // 7
  final pollOld = r'''      // ── Step 1: If we are already waiting for a ride confirmation ──
      if (_waitingForRideId != null) {
        // Throttle: only call getRide every 3rd tick (~15–30 s) to reduce spam
        _waitingCheckTickCount++;
        if (_waitingCheckTickCount % 3 != 0) {
          debugPrint(
            '⏳ Waiting tick $_waitingCheckTickCount — skipping getRide, next check at tick ${_waitingCheckTickCount + (3 - _waitingCheckTickCount % 3)}',
          );
        } else {
          final res = await ApiService.getRide(_waitingForRideId!);
          if (res.success && res.data.isNotEmpty) {
            final ride = ApiService.unwrapRidePayload(res.data);
            final status = RideStatus.normalize(ride['status']?.toString());
            final assignedDriverId =
                ride['driverId']?.toString() ??
                ride['assignedDriverId']?.toString() ??
                '';

            if (assignedDriverId == driverId) {
              // The passenger confirmed us! Show an accept/decline popup
              debugPrint('🎯 User assigned ride $_waitingForRideId to us! Showing confirmation popup...');
              
              setState(() {
                _waitingForRideId = null;
                _waitingForRideData = null;
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
                // Show RideRequestScreen as the final accept/decline step.
                // This time the label is "Accept Ride" instead of "I'm Available".
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RideRequestScreen(
                      rideId: res.data['_id']?.toString() ?? '',
                      pickup: pickup,
                      destination: destination,
                      rideType: rType,
                      distance: dist != '—' ? dist : '—',
                      duration: dur != '—' ? dur : '—',
                      fare: fare,
                      isAssigned: true, // ← tells screen to show "Accept Ride"
                    ),
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() => _isShowingRequestScreen = false);
                }
              }

              if (!mounted) return;

              if (result == 'interested' || result == 'accepted') {
                // Driver accepted — call the accept API then navigate
                debugPrint('✅ [ACCEPT] Calling acceptRide API for ${res.data['_id']}');
                final driverIdForAccept = driverId;
                ApiService.acceptRide(
                  rideId: res.data['_id']?.toString() ?? '',
                  driverId: driverIdForAccept,
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
                        rideId: res.data['_id']?.toString() ?? '',
                        pickup: pickup,
                        destination: destination,
                        rideType: rType,
                        distance: dist != '—' ? dist : '—',
                        duration: dur != '—' ? dur : '—',
                        fare: fare, // ← pass fare so driver sees it immediately
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
                // User can just go back online or wait.
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
                  '⏸️ Driver is no longer in the interested list for $_waitingForRideId. Clearing waiting state.');
              setState(() {
                _waitingForRideId = null;
                _waitingForRideData = null;
              });
            } else if (assignedDriverId.isNotEmpty &&
                assignedDriverId != driverId) {
              debugPrint(
                  '⏸️ Ride $_waitingForRideId was assigned to another driver. Clearing waiting state.');
              setState(() {
                _waitingForRideId = null;
                _waitingForRideData = null;
              });
            } else if (status == 'cancelled' || status == 'completed') {
              debugPrint(
                  '⏸️ Ride $_waitingForRideId status changed to $status. Clearing waiting state.');
              setState(() {
                _waitingForRideId = null;
                _waitingForRideData = null;
              });
            }
          } else {
            debugPrint(
                '⏸️ getRide failed (status=${res.statusCode}). Clearing waiting state for $_waitingForRideId.');
            if (res.statusCode == 404) {
              await _markRideIgnored(_waitingForRideId!);
            }
            setState(() {
              _waitingForRideId = null;
              _waitingForRideData = null;
            });
          }
        }
      }''';
  final pollNew = r'''      // ── Step 1: If we are already waiting for ride confirmations ──
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
                debugPrint('🎯 User assigned ride $rideId to us! Showing confirmation popup...');
                
                setState(() {
                  _waitingRides.remove(rideId);
                  _isOnline = false;
                  _isShowingRequestScreen = true;
                });
                _pollTimer?.cancel();

                final pickup = ride['pickupLocation']?.toString() ?? ride['pickup']?.toString() ?? 'Pickup';
                final destination = ride['dropoffLocation']?.toString() ?? ride['destination']?.toString() ?? 'Destination';
                final rType = ride['rideType']?.toString() ?? ride['vehicleType']?.toString() ?? _vehicleType;
                final dist = ApiService.formatDistanceDisplay(ride['distance'] ?? ride['distanceKm']);
                final dur = ApiService.formatDurationDisplay(ride['duration'] ?? ride['durationMin']);
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
                    distanceKm: ApiService.parseDistanceKm(ride['distanceKm'] ?? ride['distance']),
                    duration: dur != '—' ? dur : null,
                    durationMin: ApiService.parseDurationMin(ride['durationMin'] ?? ride['duration']),
                  ).then((res) {
                    debugPrint(res.success ? '✅ [ACCEPT] acceptRide succeeded' : '⚠️ [ACCEPT] acceptRide failed: ${res.errorMessage}');
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
                }
                return; // End poll tick since we navigated
              }

              final List<dynamic> interested = List.from(ride['availableDrivers'] ?? ride['interestedDrivers'] ?? []);
              final isInterested = interested.map((e) => e.toString()).contains(driverId);

              if (!isInterested && assignedDriverId != driverId) {
                debugPrint('⏸️ Driver is no longer in the interested list for $rideId. Clearing waiting state.');
                setState(() => _waitingRides.remove(rideId));
              } else if (assignedDriverId.isNotEmpty && assignedDriverId != driverId) {
                debugPrint('⏸️ Ride $rideId was assigned to another driver. Clearing waiting state.');
                setState(() => _waitingRides.remove(rideId));
              } else if (status == 'cancelled' || status == 'completed') {
                debugPrint('⏸️ Ride $rideId status changed to $status. Clearing waiting state.');
                setState(() => _waitingRides.remove(rideId));
              } else {
                setState(() => _waitingRides[rideId] = ride);
              }
            } else {
              debugPrint('⏸️ getRide failed (status=${res.statusCode}). Clearing waiting state for $rideId.');
              if (res.statusCode == 404) await _markRideIgnored(rideId);
              setState(() => _waitingRides.remove(rideId));
            }
          }
        }
      }''';
  c = c.replaceAll(pollOld, pollNew);

  // 8
  final step4Old = r'''          if (_waitingForRideId == rId) {
            // Already waiting for this ride, skip showing popup again
            continue;
          }''';
  final step4New = r'''          if (_waitingRides.containsKey(rId)) {
            // Already in waiting list (interested), skip showing popup again
            continue;
          }''';
  c = c.replaceAll(step4Old, step4New);

  // 9
  final step4DebugOld = r'''      debugPrint(
        'STEP 4: _isShowingRequestScreen=$_isShowingRequestScreen, waitingId=$_waitingForRideId, _isOnline=$_isOnline',
      );''';
  final step4DebugNew = r'''      debugPrint(
        'STEP 4: _isShowingRequestScreen=$_isShowingRequestScreen, waitingCount=${_waitingRides.length}, _isOnline=$_isOnline',
      );''';
  c = c.replaceAll(step4DebugOld, step4DebugNew);

  
  final distOld = r'''    // Apply 15 km Radius filter between driver's current position and ride pickup
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
            '⏸️ Broadcast Ride  is too far ( km). Max limit 15 km.',
          );
          return false;
        }
      }
    }''';
  final distNew = r'''    // Apply 15 km Radius filter between driver's current position and ride pickup
    // NOTE: Radius filter has been removed from the frontend.''';
  c = c.replaceAll(distOld, distNew);

  file.writeAsStringSync(c);
  print('Dart fix completed.');
}
