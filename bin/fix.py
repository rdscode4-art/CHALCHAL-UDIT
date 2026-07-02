import re

with open('lib/features/driver/screens/driver_home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Variables
text = re.sub(
    r'String\? _waitingForRideId;\s*Map<String, dynamic>\? _waitingForRideData;',
    r'Map<String, Map<String, dynamic>> _waitingRides = {};',
    text
)

# 2. Distance Filter
text = re.sub(
    r'final pickupLatVal =[^}]*if \(distanceMeters > 15000\) \{[^}]*\}[^}]*\}[^}]*\}',
    r'''// NOTE: Radius filter has been removed from the frontend.
    // The backend is now fully responsible for filtering rides by distance.''',
    text, flags=re.DOTALL
)

# 3. FCM push
text = re.sub(
    r'if \(_waitingForRideId == rideId\) \{\s*debugPrint\([^\n]*\);\s*setState\(\(\) \{\s*_waitingForRideId = null;\s*_waitingForRideData = null;\s*\}\);\s*\}',
    r'''if (_waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride assigned to us! Clearing waiting state.');
        setState(() {
          _waitingRides.remove(rideId);
        });
      }''',
    text, flags=re.DOTALL
)

# 4. FCM cancel
text = re.sub(
    r'if \(rideId\.isNotEmpty && _waitingForRideId == rideId\) \{\s*debugPrint\([^\n]*\);\s*if \(mounted\) \{\s*setState\(\(\) \{\s*_waitingForRideId = null;\s*_waitingForRideData = null;\s*\}\);\s*\}\s*\}',
    r'''if (rideId.isNotEmpty && _waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride cancelled by user. Clearing waiting state.');
        if (mounted) {
          setState(() {
            _waitingRides.remove(rideId);
          });
        }
      }''',
    text, flags=re.DOTALL
)

# 5. _showRideRequestScreen assignment
text = re.sub(
    r'if \(mounted\) \{\s*setState\(\(\) \{\s*_waitingForRideId = [^;]+;\s*_waitingForRideData = [^;]+;\s*\}\);\s*\}',
    r'''if (mounted) {
                setState(() {
                  _waitingRides[rideId] = ride;
                });
              }''',
    text, flags=re.DOTALL
)

# 6. cancelInterest
text = re.sub(
    r'void _cancelInterest\(\) \{\s*if \(_waitingForRideId == null\) return;\s*setState\(\(\) \{\s*_waitingForRideId = null;\s*_waitingForRideData = null;\s*\}\);\s*\}',
    r'''Future<void> _cancelInterest(String rideId) async {
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
  }''',
    text, flags=re.DOTALL
)

# 7. Polling Tick
text = re.sub(
    r'if \(_waitingForRideId != null\) \{[^}]*Step 2: Leave local queued',
    r'''if (_waitingRides.isNotEmpty) {
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
      }
      
      // Step 2: Leave local queued''',
    text, flags=re.DOTALL
)

# 8. Step 4 Check
text = re.sub(
    r'if \(!_isShowingRequestScreen &&\s*mounted &&\s*_isOnline &&\s*_waitingForRideId == null &&\s*!_isHandlingAssignment\)',
    r'''if (!_isShowingRequestScreen &&
          mounted &&
          _isOnline &&
          !_isHandlingAssignment)''',
    text, flags=re.DOTALL
)

text = re.sub(
    r'if \(_waitingForRideId == rId\) \{\s*// Already waiting for this ride, skip showing popup again\s*continue;\s*\}',
    r'''if (_waitingRides.containsKey(rId)) {
            // Already in waiting list (interested), skip showing popup again
            continue;
          }''',
    text, flags=re.DOTALL
)

# 9. Debug log
text = re.sub(r'_waitingForRideId=\$_waitingForRideId', r'waitingCount=${_waitingRides.length}', text)

# 10. Banner
text = re.sub(
    r'if \(_waitingForRideId != null && _waitingForRideData != null\) \.\.\.\[.*?\],',
    r'''            ..._waitingRides.entries.map((entry) {
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
            }).toList(),''',
    text, flags=re.DOTALL
)

with open('lib/features/driver/screens/driver_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Done')
