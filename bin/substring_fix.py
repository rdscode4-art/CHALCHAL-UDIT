import os

with open('lib/features/driver/screens/driver_home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\\r\\n', '\\n')

def replace_between(start_str, end_str, replacement):
    global text
    start = text.find(start_str)
    if start == -1:
        print(f"Could not find start: {start_str[:40]}")
        return
    end = text.find(end_str, start)
    if end == -1:
        print(f"Could not find end: {end_str[:40]}")
        return
    text = text[:start] + replacement + text[end + len(end_str):]

# 1. Variables
replace_between(
    'String? _waitingForRideId;',
    'Map<String, dynamic>? _waitingForRideData;',
    'Map<String, Map<String, dynamic>> _waitingRides = {};'
)

# 2. Distance Filter
replace_between(
    '    final pickupLatVal =',
    '        if (distanceMeters > 15000) {\n          debugPrint(\n            \'⏸️ Broadcast Ride $rideId is too far (${(distanceMeters / 1000).toStringAsFixed(1)} km). Max limit 15 km.\',\n          );\n          return false;\n        }\n      }\n    }',
    '''    // NOTE: Radius filter has been removed from the frontend.
    // The backend is now fully responsible for filtering rides by distance.'''
)

# 3. FCM push
replace_between(
    '      if (_waitingForRideId == rideId) {',
    '        });\n      }',
    '''      if (_waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride assigned to us! Clearing waiting state.');
        setState(() {
          _waitingRides.remove(rideId);
        });
      }'''
)

# 4. FCM cancel
start_str = "      if (rideId.isNotEmpty && _waitingForRideId == rideId) {"
end_str = "          });\n        }\n      }"
replace_between(
    start_str,
    end_str,
    '''      if (rideId.isNotEmpty && _waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride cancelled by user. Clearing waiting state.');
        if (mounted) {
          setState(() {
            _waitingRides.remove(rideId);
          });
        }
      }'''
)

# 5. showRideRequestScreen
replace_between(
    '              if (mounted) {\n                setState(() {\n                  _waitingForRideId = rideId;',
    '                  _waitingForRideData = ride;\n                });\n              }',
    '''              if (mounted) {
                setState(() {
                  _waitingRides[rideId] = ride;
                });
              }'''
)

# 6. _cancelInterest
replace_between(
    '  void _cancelInterest() {\n    if (_waitingForRideId == null) return;\n    setState(() {\n      _waitingForRideId = null;\n      _waitingForRideData = null;\n    });\n  }',
    '  void _cancelInterest() {\n    if (_waitingForRideId == null) return;\n    setState(() {\n      _waitingForRideId = null;\n      _waitingForRideData = null;\n    });\n  }',
    '''  Future<void> _cancelInterest(String rideId) async {
    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) return;

    setState(() {
      _waitingRides.remove(rideId);
    });

    try {
      await ApiService.cancelDriverInterest(rideId: rideId, driverId: driverId);
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
  }'''
)

# 7. Polling Tick
replace_between(
    '      if (_waitingForRideId != null) {',
    '        }\n      }',
    '''      if (_waitingRides.isNotEmpty) {
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
                  await _markRideIgnored(rideId);
                  ApiService.rejectRide(rideId: rideId, driverId: driverId).then((res) {});
                  unawaited(_markDriverNotInterested(rideId, driverId));
                  if (mounted) {
                    setState(() => _isOnline = true);
                    _startPolling();
                  }
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
      }'''
)

# 8. Step 4 Check
text = text.replace(
    'if (!_isShowingRequestScreen &&\n          mounted &&\n          _isOnline &&\n          _waitingForRideId == null &&\n          !_isHandlingAssignment) {',
    'if (!_isShowingRequestScreen &&\n          mounted &&\n          _isOnline &&\n          !_isHandlingAssignment) {'
)

text = text.replace(
    '          if (_waitingForRideId == rId) {\n            // Already waiting for this ride, skip showing popup again\n            continue;\n          }',
    '''          if (_waitingRides.containsKey(rId)) {
            // Already in waiting list (interested), skip showing popup again
            continue;
          }'''
)

# 9. Debug log
text = text.replace(
    '_waitingForRideId=$_waitingForRideId',
    'waitingCount=${_waitingRides.length}'
)

# 10. Banner
start_str = "            if (_waitingForRideId != null && _waitingForRideData != null) ...["
end_str = "                  ],\n                ),\n              ),\n            ],"
replace_between(
    start_str,
    end_str,
    '''            ..._waitingRides.entries.map((entry) {
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
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final driverId = await SessionService.getDriverId();
                            if (!mounted || driverId == null || driverId.isEmpty || rideId.isEmpty) {
                              return;
                            }
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
                          label: const Text('Chat with Passenger'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentStrong,
                            side: BorderSide(
                              color: AppColors.accentStrong.withAlpha(160),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (rideId.isNotEmpty) {
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              await _cancelInterest(rideId);
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Interest cancelled successfully.'),
                                  backgroundColor: AppColors.accentRed,
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: AppColors.accentRed,
                          ),
                          label: const Text(
                            'Cancel Interest',
                            style: TextStyle(color: AppColors.accentRed),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentRed,
                            side: const BorderSide(color: AppColors.accentRed),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),'''
)

# Some isolated wait clears
text = text.replace(
    '                _waitingForRideId = rId;\n                _waitingForRideData = ride;\n                _interestReflected = true;',
    '                _waitingRides[rId] = ride;\n                _interestReflected = true;'
)
text = text.replace(
    '      _waitingForRideId = null;\n      _waitingForRideData = null;',
    '      // removed single wait clear'
)

with open('lib/features/driver/screens/driver_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Substring script completed')
