/// In-memory driver store.
/// In production this would be backed by Firestore / a REST API.
class DriverRepository {
  // ── Registered drivers ────────────────────────────────────────────────────
  static final List<Map<String, dynamic>> _registeredDrivers = [
    {
      'id': 'd1',
      'name': 'Aman Kumar',
      'phone': '+91 98765 43210',
      'vehicle': 'Toyota Etios',
      'vehicleNumber': 'DL 4C AB 1234',
      'vehicleType': 'ev',
      'eta': '3 mins',
      'rating': '4.8',
      'license': 'DL4ABC1234',
      'experience': '5 yrs',
      'status': 'Online',
      'distanceKm': '1.2',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
    {
      'id': 'd2',
      'name': 'Neha Sharma',
      'phone': '+91 91234 56789',
      'vehicle': 'Maruti Dzire',
      'vehicleNumber': 'DL 5C AB 4321',
      'vehicleType': 'sedan',
      'eta': '4 mins',
      'rating': '4.7',
      'license': 'DL5ABC4321',
      'experience': '6 yrs',
      'status': 'Online',
      'distanceKm': '2.4',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
    {
      'id': 'd3',
      'name': 'Ravi Patel',
      'phone': '+91 99887 66554',
      'vehicle': 'Hyundai Aura',
      'vehicleNumber': 'DL 8C AB 6543',
      'vehicleType': 'ev',
      'eta': '6 mins',
      'rating': '4.6',
      'license': 'DL8ABC6543',
      'experience': '4 yrs',
      'status': 'Offline',
      'distanceKm': '3.8',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
    {
      'id': 'd4',
      'name': 'Priya Singh',
      'phone': '+91 97654 32109',
      'vehicle': 'Honda Activa',
      'vehicleNumber': 'DL 2C AB 9876',
      'vehicleType': 'bike',
      'eta': '2 mins',
      'rating': '4.9',
      'license': 'DL2ABC9876',
      'experience': '3 yrs',
      'status': 'Online',
      'distanceKm': '0.8',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
    {
      'id': 'd5',
      'name': 'Suresh Yadav',
      'phone': '+91 96543 21098',
      'vehicle': 'Bajaj RE Auto',
      'vehicleNumber': 'DL 6C AB 5432',
      'vehicleType': 'auto',
      'eta': '5 mins',
      'rating': '4.5',
      'license': 'DL6ABC5432',
      'experience': '7 yrs',
      'status': 'Online',
      'distanceKm': '1.9',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
    {
      'id': 'd6',
      'name': 'Vikram Singh',
      'phone': '+91 95432 10987',
      'vehicle': 'Mahindra XUV500',
      'vehicleNumber': 'DL 7C AB 7654',
      'vehicleType': 'suv',
      'eta': '7 mins',
      'rating': '4.8',
      'license': 'DL7ABC7654',
      'experience': '8 yrs',
      'status': 'Online',
      'distanceKm': '3.2',
      'verificationStatus': 'verified',
      'rejectionReason': '',
    },
  ];

  // ── Currently logged-in driver session ────────────────────────────────────
  /// Set this when a driver logs in or registers.
  /// Cleared on logout.
  static Map<String, dynamic>? currentDriver;

  // ── Public API ────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> get availableDrivers =>
      _registeredDrivers.map((d) => Map<String, dynamic>.from(d)).toList();

  static void registerDriver(Map<String, dynamic> driver) {
    final d = {
      'id': 'd${DateTime.now().millisecondsSinceEpoch}',
      'name': driver['name'] ?? 'Unknown Driver',
      'phone': driver['phone'] ?? '',
      'vehicle': driver['vehicle'] ?? 'Unknown Vehicle',
      'vehicleNumber': driver['vehicleNumber'] ?? '',
      'vehicleType': driver['vehicleType'] ?? 'auto',
      'vehicleRc': driver['vehicleRc'] ?? '',
      'aadhaar': driver['aadhaar'] ?? '',
      'eta': driver['eta'] ?? '2 mins',
      'rating': driver['rating'] ?? '4.9',
      'license': driver['license'] ?? '',
      'experience': driver['experience'] ?? '0 yrs',
      'status': 'Online',
      'distanceKm': driver['distanceKm'] ?? '0.0',
      'verificationStatus': driver['verificationStatus'] ?? 'pending',
      'rejectionReason': driver['rejectionReason'] ?? '',
    };
    _registeredDrivers.insert(0, d);
    currentDriver = Map<String, dynamic>.from(d);
  }

  static void logout() {
    currentDriver = null;
  }
}
