import os

with open('lib/features/driver/screens/driver_home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

out = []
skip = False
block_end_marker = None

for i, line in enumerate(lines):
    if skip:
        if block_end_marker == 'distance_filter' and '}' in line and 'if (distanceMeters > 15000)' in lines[i-7]:
            skip = False
            continue
        if block_end_marker == 'fcm_assigned' and '});' in line and i > 0 and 'setState(() {' in lines[i-4]:
            skip = False
            out.append('      }\n')
            continue
        if block_end_marker == 'fcm_cancelled' and '}' in line and i > 0 and 'setState(() {' in lines[i-5]:
            skip = False
            out.append('        }\n')
            out.append('      }\n')
            continue
        if block_end_marker == 'cancel_interest' and '});' in line and 'void _cancelInterest' in lines[i-5]:
            skip = False
            out.append('  }\n')
            continue
        if block_end_marker == 'poll_loop' and 'Step 2: Leave local queued' in line:
            skip = False
            out.append(line)
            continue
        if block_end_marker == 'step4_debug' and ');' in line and '_waitingForRideId' in lines[i-1]:
            skip = False
            out.append(line)
            continue
        if block_end_marker == 'banner' and '],' in line and 'if (_waitingForRideId != null && _waitingForRideData != null)' in lines[i-136]:
            skip = False
            # We don't append the line here because our replacement includes `],` or we already replaced it
            continue
            
        continue

    # 1. State vars
    if 'String? _waitingForRideId;' in line:
        out.append('  Map<String, Map<String, dynamic>> _waitingRides = {};\n')
        continue
    if 'Map<String, dynamic>? _waitingForRideData;' in line:
        continue

    # 2. Distance filter
    if 'final pickupLatVal =' in line and 'Apply 15 km Radius filter' in lines[i-1]:
        out.append('    // NOTE: Radius filter has been removed from the frontend.\n')
        out.append('    // The backend is now fully responsible for filtering rides by distance.\n')
        skip = True
        block_end_marker = 'distance_filter'
        continue
        
    # 3. FCM push
    if 'if (_waitingForRideId == rideId) {' in line and 'FCM: Ride assigned' in lines[i+1]:
        out.append('''      if (_waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride assigned to us! Clearing waiting state.');
        setState(() {
          _waitingRides.remove(rideId);
''')
        skip = True
        block_end_marker = 'fcm_assigned'
        continue
        
    # 4. FCM cancel
    if 'if (rideId.isNotEmpty && _waitingForRideId == rideId) {' in line and 'FCM: Ride cancelled' in lines[i+1]:
        out.append('''      if (rideId.isNotEmpty && _waitingRides.containsKey(rideId)) {
        debugPrint('🔔 FCM: Ride cancelled by user. Clearing waiting state.');
        if (mounted) {
          setState(() {
            _waitingRides.remove(rideId);
''')
        skip = True
        block_end_marker = 'fcm_cancelled'
        continue

    # 5. _showRideRequestScreen assignment
    if '_waitingForRideId = rId;' in line:
        out.append('                  _waitingRides[rId] = ride;\n')
        continue
    if '_waitingForRideData = ride;' in line:
        continue
    if '_waitingForRideId = rideId;' in line:
        out.append('                  _waitingRides[rideId] = ride;\n')
        continue
    if '_waitingForRideData = rideData;' in line:
        continue
    if '_waitingForRideId = null;' in line and 'setState(() {' in lines[i-1] and '_cancelInterest' not in lines[i-2] and 'FCM' not in ''.join(lines[i-10:i]):
        out.append('                  // removed single wait clear\n')
        continue
    if '_waitingForRideData = null;' in line and 'setState(() {' in lines[i-2]:
        continue

    # 6. cancelInterest
    if 'void _cancelInterest() {' in line:
        out.append('''  Future<void> _cancelInterest(String rideId) async {
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
''')
        skip = True
        block_end_marker = 'cancel_interest'
        continue

    # 7. Polling Tick
    if 'if (_waitingForRideId != null) {' in line and 'Step 1: If we are already waiting' in lines[i-1]:
        out.append('''      if (_waitingRides.isNotEmpty) {
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
      }\n''')
        skip = True
        block_end_marker = 'poll_loop'
        continue
        
    # 8. Step 4 Check
    if 'if (!_isShowingRequestScreen &&' in line and '_waitingForRideId == null &&' in lines[i+1]:
        out.append('      if (!_isShowingRequestScreen &&\n')
        out.append('          mounted &&\n')
        out.append('          _isOnline &&\n')
        out.append('          !_isHandlingAssignment) {\n')
        # Clear the next 3 lines
        lines[i+1] = ''
        lines[i+2] = ''
        lines[i+3] = ''
        continue
    
    if 'if (_waitingForRideId == rId) {' in line and 'Already waiting' in lines[i+1]:
        out.append('          if (_waitingRides.containsKey(rId)) {\n')
        continue

    # 9. Debug log
    if '_waitingForRideId=$_waitingForRideId' in line:
        out.append(line.replace('_waitingForRideId=$_waitingForRideId', 'waitingCount=${_waitingRides.length}'))
        continue
        
    # 10. Banner
    if 'if (_waitingForRideId != null && _waitingForRideData != null) ...[' in line:
        out.append('''            ..._waitingRides.entries.map((entry) {
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
            }).toList(),\n''')
        skip = True
        block_end_marker = 'banner'
        continue
        
    out.append(line)

with open('lib/features/driver/screens/driver_home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(out)
print('Line-by-line script completed')
