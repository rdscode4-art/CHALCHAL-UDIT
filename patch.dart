  Future<void> _handleNewRequestPush(String rideId) async {
    if (!mounted) return;
    if (_isShowingRequestScreen) {
      debugPrint('[FCM] Request screen already active, skipping new_request push for rideId: $rideId');
      return;
    }
    if (_shownRideIds.contains(rideId) || _ignoredRideIds.contains(rideId)) return;

    final driverId = await SessionService.getDriverId();
    if (driverId == null || driverId.isEmpty) return;

    final res = await ApiService.getRide(rideId);
    if (!mounted) return;
    if (res.statusCode == 404 || !res.success || res.data.isEmpty) {
      await _markRideIgnored(rideId);
      return;
    }

    final rideData = ApiService.normalizeDriverRidePayload(
      res.data,
      fallbackDriverId: driverId,
    );

    RideRequestService.queueRideRequest(rideData);

    final pickup = rideData['pickupLocation']?.toString() ?? rideData['pickup']?.toString() ?? 'Pickup';
    final destination = rideData['destination']?.toString() ?? rideData['dropoffLocation']?.toString() ?? 'Destination';
    final rType = rideData['rideType']?.toString() ?? rideData['vehicleType']?.toString() ?? _vehicleType;
    final dist = ApiService.formatDistanceDisplay(rideData['distance'] ?? rideData['distanceKm']);
    final dur = ApiService.formatDurationDisplay(rideData['duration'] ?? rideData['durationMin']);
    final fareNum = ApiService.resolveRideFare(rideData);
    final fare = fareNum?.toString();

    _pollTimer?.cancel();
    if (mounted) setState(() => _isShowingRequestScreen = true);

    await _markRideAsShown(rideId, driverId);

    String? result;
    try {
      result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => RideRequestScreen(
            rideId: rideId,
            pickup: pickup,
            destination: destination,
            distance: dist != '—' ? dist : '—',
            rideType: rType,
            duration: dur != '—' ? dur : '—',
            fare: fare,
            isAssigned: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isShowingRequestScreen = false);
    }

    if (!mounted) return;

    if (result == 'interested') {
      setState(() {
        _waitingForRideId = rideId;
        _waitingForRideData = rideData;
        _interestReflected = true;
        _waitingCheckTickCount = 0;
      });
      _startPolling();
    } else {
      await _markRideIgnored(rideId);
      RideRequestService.removeRequestByRideId(rideId);
      _startPolling();
    }
  }
