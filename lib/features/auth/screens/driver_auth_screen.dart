import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/firebase_notification_service.dart';
import '../../../core/utils/device_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/vehicle_utils.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../services/category_service.dart';
import '../../driver/data/driver_repository.dart';
import '../../driver/screens/driver_home_screen.dart';
import '../../../core/localization/app_localizations.dart';

/// OTP-based authentication flow for drivers:
///
///   Step 1 → Enter phone  → POST /api/auth/send-otp  (role: driver)
///   Step 2 → Enter OTP   → POST /api/auth/verify-otp (role: driver)
///     • isNewUser: false  → save session, go to DriverHomeScreen
///     • isNewUser: true   → show full registration form (KYC docs)
///   Step 3 (new drivers) → POST /api/drivers/complete-profile (multipart)
class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({super.key});
  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

enum _DriverStep { phone, otp, register }

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  _DriverStep _step = _DriverStep.phone;
  bool _loading = false;
  String? _error;

  // Phone (stored after OTP sent)
  String _phone = '';

  // Step 1
  final _phoneCtrl = TextEditingController();

  // Step 2
  final _otpCtrl = TextEditingController();

  // Step 3 — Registration fields
  final _nameCtrl = TextEditingController();
  final _vehicleNoCtrl = TextEditingController();
  String _selectedVehicleType = 'auto';

  // Vehicle categories fetched from backend
  List<Map<String, String>> _vehicleCategories = const [
    {'key': 'bike', 'name': 'Bike'},
    {'key': 'auto', 'name': 'Auto'},
    {'key': 'ev', 'name': 'EV'},
    {'key': 'sedan', 'name': 'Sedan'},
    {'key': 'suv', 'name': 'SUV'},
  ];
  bool _loadingCategories = false;

  // Document file paths (XFile for cross-platform content URI support)
  XFile? _profilePic;
  XFile? _licensePic;
  XFile? _aadharFrontPic;
  XFile? _aadharBackPic;
  XFile? _rcPic;
  XFile? _insurancePic;
  XFile? _pucPic;
  // Keep path strings for API compat — populated from XFile.path after pick
  String _profilePicPath = '';
  String _licensePicPath = '';
  String _aadharFrontPicPath = '';
  String _aadharBackPicPath = '';
  String _rcPicPath = '';
  String _insurancePicPath = '';
  String _pucPicPath = '';

  // Display controllers for file name
  final _profilePicCtrl = TextEditingController();
  final _licensePicCtrl = TextEditingController();
  final _aadharFrontPicCtrl = TextEditingController();
  final _aadharBackPicCtrl = TextEditingController();
  final _rcPicCtrl = TextEditingController();
  final _insurancePicCtrl = TextEditingController();
  final _pucPicCtrl = TextEditingController();

  // Document number text fields (required by backend)
  final _licenseNumberCtrl = TextEditingController();
  final _aadharNumberCtrl = TextEditingController();

  // Zone requirements
  Set<String>? _requiredDocs;
  bool _loadingZone = false;

  bool _docRequired(String doc) {
    if (_requiredDocs == null || _requiredDocs!.isEmpty) return true;
    return _requiredDocs!.contains(doc.toLowerCase());
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadZoneRequirements();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final cats = await CategoryService.instance.fetchCategories(
        role: 'driver',
      );
      if (!mounted || cats.isEmpty) return;
      final items = cats
          .map((c) => {'key': c.key, 'name': c.name})
          .where((m) => m['key']!.isNotEmpty)
          .toList();
      if (items.isEmpty) return;
      setState(() {
        _vehicleCategories = items;
        // Keep current selection if it's still valid, else pick first
        if (!items.any((m) => m['key'] == _selectedVehicleType)) {
          _selectedVehicleType = items.first['key']!;
        }
        _loadingCategories = false;
      });
    } catch (e) {
      debugPrint('[CATEGORIES] Failed to load: $e');
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadZoneRequirements() async {
    setState(() => _loadingZone = true);
    try {
      final res = await ApiService.getActiveZones();
      if (res.success) {
        final zones = res.data['zones'];
        if (zones is List && zones.isNotEmpty) {
          final first = zones.first;
          if (first is Map) {
            final raw = first['requiredKycDocs'];
            if (raw is List) {
              final docs = raw
                  .map((e) => e.toString().toLowerCase().trim())
                  .toSet();
              if (mounted) setState(() => _requiredDocs = docs);
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZONE] $e');
    } finally {
      if (mounted) setState(() => _loadingZone = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setError(String? e) => setState(() => _error = e);
  void _setLoading(bool v) => setState(() => _loading = v);

  void _showPermissionDialog(String title, String content, VoidCallback onOpenSettings) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onOpenSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _goTo(_DriverStep s) => setState(() {
    _step = s;
    _error = null;
  });

  Future<void> _pickPhoto({
    required void Function(XFile file, String displayName) onPicked,
  }) async {
    final typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      final displayName = file.name.isNotEmpty
          ? file.name
          : path.basename(file.path);
      setState(() => onPicked(file, displayName));
    }
  }

  // ── Step 1: Send OTP ──────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      _setError(context.tr('errEnterMobile'));
      return;
    }
    if (looksLikeVehicleNumber(raw)) {
      _setError(context.tr('errLooksLikeVehicle'));
      return;
    }
    if (!isValidIndianMobile(raw)) {
      _setError(context.tr('errValidMobile'));
      return;
    }

    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      final requested = await Permission.notification.request();
      if (!requested.isGranted) {
        _showPermissionDialog(
          'Notification Required',
          'Please enable notifications to receive OTPs and ride updates.',
          () => openAppSettings(),
        );
        return;
      }
    }

    _setLoading(true);
    _setError(null);

    final phone = get10DigitPhone(raw);
    final fcmToken = await FirebaseNotificationService().getToken();

    final res = await ApiService.sendOtp(
      phone: phone,
      role: 'driver',
      fcmToken: fcmToken,
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? context.tr('errReachServer'));
      return;
    }

    _phone = phone;
    _goTo(_DriverStep.otp);
  }

  // ── Step 2: Verify OTP ────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) {
      _setError('Please enter the OTP sent to your phone.');
      return;
    }

    _setLoading(true);
    _setError(null);

    final fcmToken = await FirebaseNotificationService().getToken();
    final deviceInfo = await DeviceUtils.getDeviceInfo();

    final res = await ApiService.verifyOtp(
      phone: _phone,
      otp: otp,
      role: 'driver',
      fcmToken: fcmToken,
      deviceInfo: deviceInfo,
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? 'Invalid OTP. Please try again.');
      return;
    }

    final isNewUser = res.data['isNewUser'] == true;

    if (isNewUser) {
      _goTo(_DriverStep.register);
    } else {
      if (res.data['previousSessionLoggedOut'] == true ||
          res.data['previousDeviceLoggedOut'] == true ||
          (res.data['message']?.toString().toLowerCase().contains('previous session logged out') ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Previous session logged out'),
            backgroundColor: AppColors.accentYellow,
          ),
        );
      }
      await _saveSessionAndNavigate(res.data);
    }
  }

  // ── Step 3: Complete driver profile ───────────────────────────────────────

  Future<void> _completeProfile() async {
    // Validate required fields
    if (_nameCtrl.text.trim().isEmpty) {
      _setError(context.tr('errEnterName'));
      return;
    }
    final vehicleRaw = _vehicleNoCtrl.text.trim();
    if (vehicleRaw.isEmpty) {
      _setError(context.tr('errEnterVehicle'));
      return;
    }
    if (!isValidIndianVehicleNumber(vehicleRaw)) {
      _setError(context.tr('errValidVehicle'));
      return;
    }

    _setLoading(true);
    _setError(null);

    // Get current location
    double lat = 28.6139, lng = 77.2090;
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 4));
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }
    } catch (e) {
      debugPrint('[LOC] $e');
    }

    final fcmToken = await FirebaseNotificationService().getToken();
    final deviceInfo = await DeviceUtils.getDeviceInfo();

    final res = await ApiService.completeDriverProfile(
      name: _nameCtrl.text.trim(),
      phone: _phone,
      vehicleType: _selectedVehicleType,
      vehicleNumber: normalizeVehicleNumber(vehicleRaw),
      lat: lat,
      lng: lng,
      fcmToken: fcmToken,
      deviceInfo: deviceInfo,
      drivingLicenseNumber: _licenseNumberCtrl.text.trim(),
      aadharNumber: _aadharNumberCtrl.text.trim(),
      profilePhotoPath: _profilePicPath,
      drivingLicenseFrontPath: _licensePicPath,
      aadharFrontPath: _aadharFrontPicPath,
      aadharBackPath: _aadharBackPicPath,
      rcPhotoPath: _rcPicPath,
      insurancePhotoPath: _insurancePicPath,
      pucPhotoPath: _pucPicPath,
      profilePhotoXFile: _profilePic,
      drivingLicenseFrontXFile: _licensePic,
      aadharFrontXFile: _aadharFrontPic,
      aadharBackXFile: _aadharBackPic,
      rcPhotoXFile: _rcPic,
      insurancePhotoXFile: _insurancePic,
      pucPhotoXFile: _pucPic,
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? context.tr('errReachServer'));
      return;
    }

    // Registration done — show success, then go to OTP step for first login
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('registrationSuccess')),
        backgroundColor: AppColors.accentStrong,
        duration: const Duration(seconds: 4),
      ),
    );

    // Backend may return token/profile directly; if so, log them in immediately
    final data = res.data;
    if (data['token'] != null || data['driver'] != null || data['id'] != null) {
      await _saveSessionAndNavigate(data);
    } else {
      // Otherwise, ask them to verify OTP again (standard pending flow)
      setState(() {
        _step = _DriverStep.phone;
        _phoneCtrl.text = _phone;
        _error = null;
      });
    }
  }

  // ── Save session & navigate ───────────────────────────────────────────────

  Future<void> _saveSessionAndNavigate(Map<String, dynamic> data) async {
    final raw = data;
    final Map<String, dynamic> driverData =
        (raw['driver'] is Map<String, dynamic>)
        ? raw['driver'] as Map<String, dynamic>
        : raw;

    final id =
        driverData['_id']?.toString() ??
        driverData['id']?.toString() ??
        driverData['driverId']?.toString() ??
        _phone;
    final name = driverData['name']?.toString() ?? 'Driver';
    final vehicleNumber = normalizeVehicleNumber(
      driverData['vehicleNumber']?.toString() ?? _vehicleNoCtrl.text.trim(),
    );
    final vehicleType = driverData['vehicleType']?.toString() ?? 'auto';
    final vehicleModel =
        driverData['vehicleModel']?.toString() ??
        driverData['vehicle']?.toString() ??
        '';
    final rating = driverData['rating']?.toString() ?? '4.9';
    final experience =
        driverData['experience']?.toString() ??
        driverData['driverVerificationDetails']?.toString() ??
        '—';
    final rawStatus =
        driverData['verificationStatus']?.toString() ??
        driverData['documentStatus']?.toString() ??
        'verified';
    final verificationStatus = rawStatus.toLowerCase() == 'approved'
        ? 'verified'
        : rawStatus.toLowerCase();
    final rejectionReason = driverData['rejectionReason']?.toString() ?? '';
    final token = raw['token']?.toString();

    // Pending / rejected guard
    if (verificationStatus == 'pending') {
      _setError(context.tr('errDriverPending'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('errDriverSubmitted')),
          backgroundColor: AppColors.accentYellow,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    if (verificationStatus == 'rejected') {
      _setError(context.tr('errDriverRejected'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('errDriverRejected')),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    await SessionService.saveDriver(
      id: id,
      name: name,
      phone: _phone,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      verificationStatus: verificationStatus,
      rejectionReason: rejectionReason,
      experience: experience,
      rating: rating,
      vehicleModel: vehicleModel,
      token: token,
    );

    await FirebaseNotificationService().uploadFcmTokenToBackend(
      userId: id,
      role: 'driver',
    );

    DriverRepository.currentDriver = {
      'id': id,
      'name': name,
      'phone': _phone,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      'vehicle': vehicleModel,
      'rating': rating,
      'experience': experience,
      'status': 'Online',
      'distanceKm': '0.0',
      'eta': '—',
      'verificationStatus': verificationStatus,
      'rejectionReason': rejectionReason,
    };

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
      (r) => false,
    );
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    _otpCtrl.clear();
    _setLoading(true);
    _setError(null);

    final fcmToken = await FirebaseNotificationService().getToken();
    final res = await ApiService.sendOtp(
      phone: _phone,
      role: 'driver',
      fcmToken: fcmToken,
    );

    if (!mounted) return;
    _setLoading(false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP resent successfully.'),
          backgroundColor: AppColors.secondary,
        ),
      );
    } else {
      _setError(res.errorMessage ?? context.tr('errReachServer'));
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    for (final c in [
      _phoneCtrl,
      _otpCtrl,
      _nameCtrl,
      _vehicleNoCtrl,
      _profilePicCtrl,
      _licensePicCtrl,
      _aadharFrontPicCtrl,
      _aadharBackPicCtrl,
      _rcPicCtrl,
      _insurancePicCtrl,
      _pucPicCtrl,
      _licenseNumberCtrl,
      _aadharNumberCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.60)
        : AppColors.textGrey;
    final borderCol = isDark ? AppColors.darkBorder : AppColors.border;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        leading: _step != _DriverStep.phone
            ? BackButton(
                color: textColor,
                onPressed: () => _goTo(
                  _step == _DriverStep.register
                      ? _DriverStep.otp
                      : _DriverStep.phone,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _headerTitle,
                    style: AppTextStyles.display.copyWith(
                      fontSize: 28,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _headerSubtitle,
                style: AppTextStyles.body.copyWith(color: subColor),
              ),
              const SizedBox(height: 28),

              // Step content
              if (_step == _DriverStep.phone) _buildPhoneStep(),
              if (_step == _DriverStep.otp) _buildOtpStep(subColor),
              if (_step == _DriverStep.register)
                _buildRegisterStep(textColor, subColor, borderCol, isDark),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.accentRed,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.accentRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // Action button
              _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentStrong,
                      ),
                    )
                  : CustomButton(
                      label: _buttonLabel,
                      color: AppColors.accentStrong,
                      onPressed: _onPrimaryAction,
                    ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step widgets ──────────────────────────────────────────────────────────

  Widget _buildPhoneStep() => CustomTextField(
    hint: context.tr('mobileNumberPlaceholder'),
    prefixIcon: Icons.phone_android_outlined,
    controller: _phoneCtrl,
    keyboardType: TextInputType.phone,
  );

  Widget _buildOtpStep(Color subColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'OTP sent to $_phone',
        style: TextStyle(color: subColor, fontSize: 13),
      ),
      const SizedBox(height: 16),
      CustomTextField(
        hint: 'Enter OTP',
        prefixIcon: Icons.lock_outline,
        controller: _otpCtrl,
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: _loading ? null : _resendOtp,
        child: Text(
          'Resend OTP',
          style: TextStyle(
            color: AppColors.accentStrong,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    ],
  );

  Widget _buildRegisterStep(
    Color textColor,
    Color subColor,
    Color borderCol,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Personal Details ──────────────────────────────────────────────
        _sectionLabel(context.tr('personalDetails'), textColor),
        const SizedBox(height: 12),

        // Profile photo
        CustomTextField(
          hint: context.tr('importProfilePhoto'),
          prefixIcon: Icons.face_outlined,
          suffixIcon: Icons.upload_file,
          controller: _profilePicCtrl,
          readOnly: true,
          onTap: () => _pickPhoto(
            onPicked: (f, n) {
              _profilePic = f;
              _profilePicPath = f.path;
              _profilePicCtrl.text = n;
            },
          ),
          onSuffixTap: () => _pickPhoto(
            onPicked: (f, n) {
              _profilePic = f;
              _profilePicPath = f.path;
              _profilePicCtrl.text = n;
            },
          ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          hint: context.tr('fullName'),
          prefixIcon: Icons.person_outline,
          controller: _nameCtrl,
        ),
        const SizedBox(height: 24),

        // ── Vehicle Details ───────────────────────────────────────────────
        _sectionLabel(context.tr('vehicleDetails'), textColor),
        const SizedBox(height: 12),

        // Vehicle type dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: _loadingCategories
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedVehicleType,
                    isExpanded: true,
                    dropdownColor: isDark
                        ? AppColors.darkSurface
                        : AppColors.surface,
                    style: TextStyle(color: textColor, fontSize: 14),
                    items: _vehicleCategories
                        .map(
                          (cat) => DropdownMenuItem<String>(
                            value: cat['key'],
                            child: Text(
                              // Capitalise first letter of API name
                              cat['name']!.isEmpty
                                  ? cat['key']!
                                  : cat['name']![0].toUpperCase() +
                                        cat['name']!.substring(1),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedVehicleType = v);
                    },
                  ),
                ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          hint: context.tr('vehicleNumberPlaceholder'),
          prefixIcon: Icons.credit_card_outlined,
          controller: _vehicleNoCtrl,
        ),
        const SizedBox(height: 24),

        // ── KYC Documents ─────────────────────────────────────────────────
        _sectionLabel(context.tr('licenseIdentity'), textColor),
        const SizedBox(height: 12),

        if (_loadingZone)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Checking zone requirements…',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ],
            ),
          ),

        if (_docRequired('drivinglicense') ||
            _docRequired('driving_license') ||
            _docRequired('license')) ...[
          // License number (text)
          CustomTextField(
            hint: 'Driving License Number',
            prefixIcon: Icons.badge_outlined,
            controller: _licenseNumberCtrl,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          // License front photo
          CustomTextField(
            hint: context.tr('importLicensePhoto'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _licensePicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _licensePic = f;
                _licensePicPath = f.path;
                _licensePicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _licensePic = f;
                _licensePicPath = f.path;
                _licensePicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_docRequired('aadhar') ||
            _docRequired('aadhaar') ||
            _docRequired('aadharcard')) ...[
          // Aadhar number (text)
          CustomTextField(
            hint: 'Aadhar Card Number',
            prefixIcon: Icons.credit_card_outlined,
            controller: _aadharNumberCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          // Aadhar front photo
          CustomTextField(
            hint: context.tr('importAadharFront'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _aadharFrontPicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _aadharFrontPic = f;
                _aadharFrontPicPath = f.path;
                _aadharFrontPicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _aadharFrontPic = f;
                _aadharFrontPicPath = f.path;
                _aadharFrontPicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            hint: context.tr('importAadharBack'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _aadharBackPicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _aadharBackPic = f;
                _aadharBackPicPath = f.path;
                _aadharBackPicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _aadharBackPic = f;
                _aadharBackPicPath = f.path;
                _aadharBackPicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_docRequired('rc') || _docRequired('registrationcertificate')) ...[
          CustomTextField(
            hint: context.tr('importRcPhoto'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _rcPicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _rcPic = f;
                _rcPicPath = f.path;
                _rcPicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _rcPic = f;
                _rcPicPath = f.path;
                _rcPicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_docRequired('insurance')) ...[
          CustomTextField(
            hint: context.tr('importInsurancePhoto'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _insurancePicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _insurancePic = f;
                _insurancePicPath = f.path;
                _insurancePicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _insurancePic = f;
                _insurancePicPath = f.path;
                _insurancePicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_docRequired('puc')) ...[
          CustomTextField(
            hint: context.tr('importPucPhoto'),
            prefixIcon: Icons.image_outlined,
            suffixIcon: Icons.upload_file,
            controller: _pucPicCtrl,
            readOnly: true,
            onTap: () => _pickPhoto(
              onPicked: (f, n) {
                _pucPic = f;
                _pucPicPath = f.path;
                _pucPicCtrl.text = n;
              },
            ),
            onSuffixTap: () => _pickPhoto(
              onPicked: (f, n) {
                _pucPic = f;
                _pucPicPath = f.path;
                _pucPicCtrl.text = n;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // ── Computed labels ───────────────────────────────────────────────────────

  String get _headerTitle {
    switch (_step) {
      case _DriverStep.phone:
        return context.tr('driverLogin');
      case _DriverStep.otp:
        return 'Verify OTP';
      case _DriverStep.register:
        return context.tr('driverSignUp');
    }
  }

  String get _headerSubtitle {
    switch (_step) {
      case _DriverStep.phone:
        return context.tr('driverLoginSub');
      case _DriverStep.otp:
        return 'Enter the OTP sent to your phone via notification.';
      case _DriverStep.register:
        return context.tr('driverSignUpSub');
    }
  }

  String get _buttonLabel {
    switch (_step) {
      case _DriverStep.phone:
        return 'Send OTP';
      case _DriverStep.otp:
        return 'Verify OTP';
      case _DriverStep.register:
        return context.tr('signUp');
    }
  }

  VoidCallback get _onPrimaryAction {
    switch (_step) {
      case _DriverStep.phone:
        return _sendOtp;
      case _DriverStep.otp:
        return _verifyOtp;
      case _DriverStep.register:
        return _completeProfile;
    }
  }

  // ── Section label helper ──────────────────────────────────────────────────

  Widget _sectionLabel(String text, Color color) => Text(
    text,
    style: AppTextStyles.heading.copyWith(fontSize: 16, color: color),
  );
}
