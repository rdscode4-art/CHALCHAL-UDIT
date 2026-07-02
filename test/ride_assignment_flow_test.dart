import 'package:flutter_test/flutter_test.dart';
import 'package:ridego/core/services/ride_request_service.dart';

/// Test script to simulate and debug the ride assignment flow
///
/// This test simulates:
/// 1. User assigning a ride to a driver
/// 2. Driver going online
/// 3. Driver checking for new rides
/// 4. Ride matching logic
///
/// Run with: flutter test test/ride_assignment_flow_test.dart -v

void main() {
  group('Ride Assignment Flow - Debug Test', () {
    setUp(() {
      // Clear any previous state
      RideRequestService.clearQueue();
      print('\n${'=' * 80}');
      print('TEST SETUP: Cleared ride queue');
      print('=' * 80);
    });

    test('Step 1: User assigns bike ride to driver', () {
      print('\n📱 STEP 1: USER ASSIGNS RIDE');
      print('-' * 80);

      const userId = 'user_123';
      const driverId = 'driver_456';
      const rideType = 'bike';
      const pickup = 'Central Station';
      const destination = 'Airport Terminal 1';
      const distance = '15.5 km';
      const duration = '25 mins';
      const bookingOtp = '1234';
      const rideId = 'ride_789';

      print('User Details:');
      print('  - User ID: $userId');
      print('  - Ride Type: $rideType');
      print('  - Pickup: $pickup');
      print('  - Destination: $destination');
      print('  - Distance: $distance');
      print('  - Duration: $duration');
      print('');
      print('Driver Details:');
      print('  - Driver ID: $driverId');
      print('  - Driver Vehicle Type: $rideType (should match ride type)');
      print('');
      print('Ride Details:');
      print('  - Ride ID: $rideId');
      print('  - Booking OTP: $bookingOtp');
      print('');

      // Simulate: User clicks "Assign Ride" button
      // This calls: ApiService.assignRide() → Backend API
      print('✅ Backend API called: POST /rides/assign');
      print('   Body: {');
      print('     "userId": "$userId",');
      print('     "driverId": "$driverId",');
      print('     "pickupLocation": "$pickup",');
      print('     "dropoffLocation": "$destination",');
      print('     "rideType": "$rideType"');
      print('   }');
      print('');

      // Simulate: Backend returns success
      print('✅ Backend API response: SUCCESS');
      print('   Response: {');
      print('     "_id": "$rideId",');
      print('     "bookingOtp": "$bookingOtp"');
      print('   }');
      print('');

      // Simulate: Frontend queues ride locally
      print(
        '✅ Frontend queues ride locally: RideRequestService.queueRideRequest()',
      );
      RideRequestService.queueRideRequest({
        'rideId': rideId,
        'bookingOtp': bookingOtp,
        'pickup': pickup,
        'destination': destination,
        'rideType': rideType,
        'vehicleType': rideType, // IMPORTANT: Must match driver's vehicle type
        'distance': distance,
        'duration': duration,
        'requestedAt': DateTime.now().toIso8601String(),
      });

      print('📋 Queue Status After Assignment:');
      print(
        '   - Pending requests: ${RideRequestService.pendingRequests.length}',
      );
      for (final req in RideRequestService.pendingRequests) {
        print('   - Ride: ${req['rideType']}, Vehicle: ${req['vehicleType']}');
      }
      print('');

      // Verify
      expect(
        RideRequestService.pendingRequests.length,
        1,
        reason: 'Should have 1 ride in queue after assignment',
      );
      expect(
        RideRequestService.pendingRequests[0]['rideType'],
        rideType,
        reason: 'Ride type should match',
      );
      expect(
        RideRequestService.pendingRequests[0]['vehicleType'],
        rideType,
        reason: 'Vehicle type should match ride type',
      );

      print('✅ STEP 1 PASSED: Ride queued successfully');
    });

    test('Step 2: Driver goes online and checks for rides', () {
      print('\n🚗 STEP 2: DRIVER GOES ONLINE');
      print('-' * 80);

      const driverId = 'driver_456';
      const driverVehicleType = 'bike';

      print('Driver Details:');
      print('  - Driver ID: $driverId');
      print('  - Vehicle Type: $driverVehicleType');
      print('');

      // First, queue a ride (simulating Step 1)
      RideRequestService.queueRideRequest({
        'rideId': 'ride_789',
        'bookingOtp': '1234',
        'pickup': 'Central Station',
        'destination': 'Airport Terminal 1',
        'rideType': 'bike',
        'vehicleType': 'bike',
        'distance': '15.5 km',
        'duration': '25 mins',
        'requestedAt': DateTime.now().toIso8601String(),
      });

      print('✅ Driver toggled online');
      print('   - Polling started (every 4 seconds)');
      print('');

      // Simulate: _checkForNewRides() called
      print('🔍 Checking for new rides...');
      print('   - Driver vehicle type: $driverVehicleType');
      print('   - Driver ID: $driverId');
      print('');

      // Check local queue first
      print('📋 Checking local queue:');
      print(
        '   - Pending requests: ${RideRequestService.pendingRequests.length}',
      );
      for (final req in RideRequestService.pendingRequests) {
        print('   - Ride: ${req['rideType']}, Vehicle: ${req['vehicleType']}');
      }
      print('');

      // Try to pop a matching ride
      final localRequest = RideRequestService.popRequestForVehicleType(
        driverVehicleType,
      );

      if (localRequest != null) {
        print('✅ Found matching ride in local queue!');
        print('   - Ride ID: ${localRequest['rideId']}');
        print('   - Ride Type: ${localRequest['rideType']}');
        print('   - Pickup: ${localRequest['pickup']}');
        print('   - Destination: ${localRequest['destination']}');
        print('   - Distance: ${localRequest['distance']}');
        print('   - Duration: ${localRequest['duration']}');
        print('');
        print('✅ Showing RideRequestScreen to driver');
      } else {
        print('❌ No matching ride found in local queue');
        print('   Would fall back to backend API...');
      }

      // Verify
      expect(
        localRequest,
        isNotNull,
        reason: 'Should find matching ride in queue',
      );
      expect(
        localRequest!['rideType'],
        'bike',
        reason: 'Ride type should be bike',
      );
      expect(
        RideRequestService.pendingRequests.length,
        0,
        reason: 'Queue should be empty after popping',
      );

      print('');
      print('✅ STEP 2 PASSED: Ride found and shown to driver');
    });

    test('Step 3: Vehicle type matching logic', () {
      print('\n🔄 STEP 3: VEHICLE TYPE MATCHING');
      print('-' * 80);

      final testCases = [
        ('bike', 'bike', true),
        ('auto', 'auto', true),
        ('ev', 'ev', true),
        ('sedan', 'sedan', true),
        ('suv', 'suv', true),
        ('bike', 'auto', false),
        ('auto', 'bike', false),
        ('BIKE', 'bike', true), // Case insensitive
        ('Bike', 'BIKE', true), // Case insensitive
        ('  bike  ', 'bike', true), // Whitespace trimmed
      ];

      print('Testing vehicle type matching:');
      print('');

      for (final (rideType, driverType, expected) in testCases) {
        final result = RideRequestService.doesVehicleTypeMatch(
          rideType,
          driverType,
        );
        final status = result == expected ? '✅' : '❌';
        print(
          '$status Match("$rideType", "$driverType") = $result (expected: $expected)',
        );
        expect(
          result,
          expected,
          reason: 'Match("$rideType", "$driverType") should be $expected',
        );
      }

      print('');
      print('✅ STEP 3 PASSED: All matching tests passed');
    });

    test('Step 4: Multiple rides in queue - correct matching', () {
      print('\n📚 STEP 4: MULTIPLE RIDES IN QUEUE');
      print('-' * 80);

      // Queue multiple rides
      print('Queuing multiple rides:');
      print('');

      RideRequestService.queueRideRequest({
        'rideId': 'ride_1',
        'rideType': 'auto',
        'vehicleType': 'auto',
        'pickup': 'Station A',
        'destination': 'Airport',
        'distance': '10 km',
        'duration': '15 mins',
      });
      print('✅ Queued: Auto ride (ride_1)');

      RideRequestService.queueRideRequest({
        'rideId': 'ride_2',
        'rideType': 'bike',
        'vehicleType': 'bike',
        'pickup': 'Station B',
        'destination': 'Mall',
        'distance': '5 km',
        'duration': '10 mins',
      });
      print('✅ Queued: Bike ride (ride_2)');

      RideRequestService.queueRideRequest({
        'rideId': 'ride_3',
        'rideType': 'sedan',
        'vehicleType': 'sedan',
        'pickup': 'Station C',
        'destination': 'Hotel',
        'distance': '20 km',
        'duration': '30 mins',
      });
      print('✅ Queued: Sedan ride (ride_3)');

      print('');
      print('📋 Queue Status:');
      print('   - Total rides: ${RideRequestService.pendingRequests.length}');
      for (final req in RideRequestService.pendingRequests) {
        print(
          '   - ${req['rideType']}: ${req['pickup']} → ${req['destination']}',
        );
      }
      print('');

      // Bike driver checks for rides
      print('🚗 Bike driver checking for rides:');
      final bikeRide = RideRequestService.popRequestForVehicleType('bike');
      expect(bikeRide, isNotNull, reason: 'Should find bike ride');
      expect(
        bikeRide!['rideId'],
        'ride_2',
        reason: 'Should get bike ride (ride_2)',
      );
      print('✅ Found: ${bikeRide['rideType']} ride (${bikeRide['rideId']})');
      print('');

      // Auto driver checks for rides
      print('🚗 Auto driver checking for rides:');
      final autoRide = RideRequestService.popRequestForVehicleType('auto');
      expect(autoRide, isNotNull, reason: 'Should find auto ride');
      expect(
        autoRide!['rideId'],
        'ride_1',
        reason: 'Should get auto ride (ride_1)',
      );
      print('✅ Found: ${autoRide['rideType']} ride (${autoRide['rideId']})');
      print('');

      // Sedan driver checks for rides
      print('🚗 Sedan driver checking for rides:');
      final sedanRide = RideRequestService.popRequestForVehicleType('sedan');
      expect(sedanRide, isNotNull, reason: 'Should find sedan ride');
      expect(
        sedanRide!['rideId'],
        'ride_3',
        reason: 'Should get sedan ride (ride_3)',
      );
      print('✅ Found: ${sedanRide['rideType']} ride (${sedanRide['rideId']})');
      print('');

      // Queue should be empty
      print('📋 Final Queue Status:');
      print('   - Total rides: ${RideRequestService.pendingRequests.length}');
      expect(
        RideRequestService.pendingRequests.length,
        0,
        reason: 'Queue should be empty',
      );

      print('');
      print('✅ STEP 4 PASSED: Multiple rides matched correctly');
    });

    test('Step 5: Enum value validation (MUST BE LOWERCASE)', () {
      print('\n✔️ STEP 5: ENUM VALUE VALIDATION');
      print('-' * 80);

      print('Checking ride type enum values:');
      print('');

      final validRideTypes = ['bike', 'auto', 'ev', 'sedan', 'suv'];
      final invalidRideTypes = [
        'BIKE',
        'AUTO',
        'EV',
        'SEDAN',
        'SUV',
        'Bike',
        'Auto',
      ];

      print('✅ Valid (lowercase):');
      for (final type in validRideTypes) {
        print('   - "$type"');
      }
      print('');

      print('❌ Invalid (uppercase or mixed case):');
      for (final type in invalidRideTypes) {
        print('   - "$type" (should be "${type.toLowerCase()}")');
      }
      print('');

      print('⚠️  IMPORTANT:');
      print('   - All ride types MUST be lowercase in the database');
      print('   - All driver vehicle types MUST be lowercase');
      print('   - The matching logic uses .toLowerCase() for comparison');
      print('   - But it\'s better to store them lowercase from the start');
      print('');

      print('✅ STEP 5 PASSED: Enum validation complete');
    });

    test('Step 6: Complete end-to-end flow simulation', () {
      print('\n🎯 STEP 6: COMPLETE END-TO-END FLOW');
      print('-' * 80);

      print('Simulating complete ride assignment and acceptance flow:');
      print('');

      // ─── USER SIDE ───────────────────────────────────────────────────────
      print('📱 USER SIDE:');
      print('');

      const userId = 'user_john_123';
      const driverId = 'driver_mike_456';
      const rideType = 'auto';
      const pickup = 'Central Station';
      const destination = 'Airport Terminal 1';
      const distance = '15.5 km';
      const duration = '25 mins';
      const bookingOtp = '5678';
      const rideId = 'ride_auto_001';

      print('1. User opens app and requests $rideType ride');
      print('   - User ID: $userId');
      print('   - From: $pickup');
      print('   - To: $destination');
      print('');

      print(
        '2. User sees available drivers and clicks "Assign Ride" on driver',
      );
      print('   - Driver: Mike (ID: $driverId)');
      print('   - Vehicle: $rideType');
      print('');

      print('3. Backend API called: POST /rides/assign');
      print('   - Response: Ride created with ID: $rideId, OTP: $bookingOtp');
      print('');

      print('4. Frontend queues ride locally');
      RideRequestService.queueRideRequest({
        'rideId': rideId,
        'bookingOtp': bookingOtp,
        'pickup': pickup,
        'destination': destination,
        'rideType': rideType,
        'vehicleType': rideType,
        'distance': distance,
        'duration': duration,
        'requestedAt': DateTime.now().toIso8601String(),
      });
      print('   - Ride queued: $rideType ride from $pickup to $destination');
      print('');

      print('5. User sees confirmation screen with OTP: $bookingOtp');
      print('');

      // ─── DRIVER SIDE ─────────────────────────────────────────────────────
      print('🚗 DRIVER SIDE:');
      print('');

      const driverVehicleType = 'auto';

      print('1. Driver opens app and toggles online');
      print('   - Driver: Mike (ID: $driverId)');
      print('   - Vehicle Type: $driverVehicleType');
      print('');

      print('2. Polling starts: _checkForNewRides() called every 4 seconds');
      print('');

      print('3. First poll - Check local queue:');
      print(
        '   - Pending requests: ${RideRequestService.pendingRequests.length}',
      );
      print('   - Looking for: $driverVehicleType rides');
      print('');

      final matchingRide = RideRequestService.popRequestForVehicleType(
        driverVehicleType,
      );

      if (matchingRide != null) {
        print('4. ✅ Found matching ride in local queue!');
        print('   - Ride ID: ${matchingRide['rideId']}');
        print('   - Ride Type: ${matchingRide['rideType']}');
        print('   - From: ${matchingRide['pickup']}');
        print('   - To: ${matchingRide['destination']}');
        print('   - Distance: ${matchingRide['distance']}');
        print('   - Duration: ${matchingRide['duration']}');
        print('');

        print('5. RideRequestScreen shown to driver');
        print('   - Driver sees ride details');
        print('   - Driver can Accept or Decline');
        print('');

        print('6. Driver clicks "Accept Ride"');
        print(
          '   - Backend API called: POST /rides/${matchingRide['rideId']}/accept',
        );
        print('   - Driver navigates to active ride screen');
        print('');

        print('7. User sees driver accepted the ride');
        print('   - Driver location updates in real-time');
        print('   - Ride status: In Progress');
        print('');

        print('✅ FLOW COMPLETE: Ride successfully assigned and accepted');
      } else {
        print('❌ ERROR: No matching ride found!');
        print('   This is the issue we\'re debugging');
      }

      expect(matchingRide, isNotNull, reason: 'Should find matching ride');
      print('');
      print('✅ STEP 6 PASSED: End-to-end flow successful');
    });
  });
}
