import os

with open('lib/features/driver/screens/driver_home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
for i, line in enumerate(lines):
    if 'Step 1: If we are already waiting for a ride confirmation' in line:
        start_idx = i
        break

if start_idx == -1:
    print("Could not find start block")
    exit(1)

# Find the start of the `if (_waitingForRideId != null) {` block
if_start_idx = -1
for i in range(start_idx, start_idx + 10):
    if 'if (_waitingForRideId != null) {' in lines[i]:
        if_start_idx = i
        break

if if_start_idx == -1:
    print("Could not find if (_waitingForRideId != null) {")
    exit(1)

# Count braces to find the end
brace_count = 0
end_idx = -1
for i in range(if_start_idx, len(lines)):
    brace_count += lines[i].count('{')
    brace_count -= lines[i].count('}')
    if brace_count == 0:
        end_idx = i
        break

if end_idx == -1:
    print("Could not find end brace")
    exit(1)

new_block = '''      if (_waitingRides.isNotEmpty) {
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
      }\n'''

lines = lines[:if_start_idx] + [new_block] + lines[end_idx + 1:]

# Next, let's fix step 3: auto populate waitingRides on broadcast fetch
# Search for `// ── Step 3: Check for broadcasted unassigned rides in the system`
step3_idx = -1
for i, line in enumerate(lines):
    if 'Step 3: Check for broadcasted unassigned rides' in line:
        step3_idx = i
        break

if step3_idx != -1:
    for i in range(step3_idx, step3_idx + 10):
        if 'if (_waitingForRideId == null) {' in lines[i]:
            # Replace it with always fetching!
            lines[i] = '      if (true) { // Always fetch broadcast rides to auto-populate _waitingRides on restart\n'
            break

# In step 3 loop, auto add to _waitingRides if we are interested
# Find `if (_shouldPresentBroadcastRide(item, driverId)) {`
# And replace the logic before it to check interest
step3_loop_idx = -1
for i in range(step3_idx, step3_idx + 40):
    if 'if (_shouldPresentBroadcastRide(item, driverId)) {' in lines[i]:
        step3_loop_idx = i
        break

if step3_loop_idx != -1:
    lines.insert(step3_loop_idx, '''
            final interestedList = List.from(item['availableDrivers'] ?? item['interestedDrivers'] ?? []);
            if (interestedList.map((e) => e.toString()).contains(driverId)) {
              if (!_waitingRides.containsKey(rId)) {
                debugPrint('🔄 Auto-recovering interested ride: $rId');
                setState(() {
                  _waitingRides[rId] = item;
                });
              }
              continue; // Already interested, skip local popup queue
            }
''')

# Next, step 4 assignment to _waitingRides
step4_idx = -1
for i in range(len(lines)):
    if 'STEP 4:' in lines[i] and 'if (!' in lines[i+1]:
        # found if (!_isShowingRequestScreen &&
        lines[i+1] = '      if (!_isShowingRequestScreen &&\n'
        if '_waitingForRideId == null &&' in lines[i+2]:
            lines[i+2] = ''
        break

# In step 4 loop, skip if already interested
for i in range(len(lines)):
    if 'STEP 4 loop: rideId=$rId' in lines[i]:
        lines.insert(i+4, '''          if (_waitingRides.containsKey(rId)) {
            continue; // Already interested
          }\n''')
        break

with open('lib/features/driver/screens/driver_home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)

print("Done")
