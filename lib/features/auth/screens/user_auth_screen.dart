import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/firebase_notification_service.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/localization/app_localizations.dart';
import '../../user/screens/user_home_screen.dart';

/// OTP-based authentication flow for users:
///
///   Step 1 → Enter phone  → POST /api/auth/send-otp
///   Step 2 → Enter OTP   → POST /api/auth/verify-otp
///     • isNewUser: false  → save session, go to HomeScreen
///     • isNewUser: true   → show name form
///   Step 3 (new users)   → Enter name → POST /api/users/complete-profile
class UserAuthScreen extends StatefulWidget {
  const UserAuthScreen({super.key});
  @override
  State<UserAuthScreen> createState() => _UserAuthScreenState();
}

enum _AuthStep { phone, otp, register }

class _UserAuthScreenState extends State<UserAuthScreen> {
  _AuthStep _step = _AuthStep.phone;
  bool _loading = false;
  String? _error;

  // Step 1
  final _phoneCtrl = TextEditingController();

  // Step 2
  final _otpCtrl = TextEditingController();

  // Step 3 (new user only)
  final _nameCtrl = TextEditingController();

  // Phone saved after OTP sent (normalised)
  String _phone = '';

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setError(String? msg) => setState(() => _error = msg);
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

  void _goTo(_AuthStep step) => setState(() {
    _step = step;
    _error = null;
  });

  // ── Step 1: Send OTP ───────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      _setError(context.tr('errEnterMobile'));
      return;
    }
    // Bug fix: use proper Indian mobile validation (same as driver screen)
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

    // Bug fix: API expects 10-digit phone, not E.164 (+91...) format
    final phone = get10DigitPhone(raw);
    final fcmToken = await FirebaseNotificationService().getToken();

    final res = await ApiService.sendOtp(
      phone: phone,
      role: 'user',
      fcmToken: fcmToken,
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? context.tr('errReachServer'));
      return;
    }

    _phone = phone;
    _goTo(_AuthStep.otp);
  }

  // ── Step 2: Verify OTP ────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    // Bug fix: OTP is 6 digits — was checking < 4 which is too loose
    if (otp.length != 6) {
      _setError('Please enter the 6-digit OTP sent to your phone.');
      return;
    }

    _setLoading(true);
    _setError(null);

    final res = await ApiService.verifyOtp(
      phone: _phone,
      otp: otp,
      role: 'user',
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? 'Invalid OTP. Please try again.');
      return;
    }

    final isNewUser = res.data['isNewUser'] == true;

    if (isNewUser) {
      // New user — collect name before completing profile
      _goTo(_AuthStep.register);
    } else {
      // Returning user — full profile is already in response
      await _saveSessionAndNavigate(res.data);
    }
  }

  // ── Step 3: Complete profile (new user) ───────────────────────────────────

  Future<void> _completeProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _setError(context.tr('errEnterName'));
      return;
    }

    _setLoading(true);
    _setError(null);

    final fcmToken = await FirebaseNotificationService().getToken();

    final res = await ApiService.completeUserProfile(
      name: name,
      phone: _phone,
      fcmToken: fcmToken,
    );

    if (!mounted) return;
    _setLoading(false);

    if (!res.success) {
      _setError(res.errorMessage ?? context.tr('errReachServer'));
      return;
    }

    await _saveSessionAndNavigate(res.data);
  }

  // ── Save session & navigate ───────────────────────────────────────────────

  Future<void> _saveSessionAndNavigate(Map<String, dynamic> data) async {
    // Response may nest user data under 'user' key
    final user = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : data;

    final id =
        user['_id']?.toString() ??
        user['id']?.toString() ??
        user['userId']?.toString() ??
        _phone;
    // Bug fix: operator precedence — wrap the fallback expression in parens
    // so ?? correctly falls back to name field before checking _nameCtrl
    final name =
        user['name']?.toString() ??
        (_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Rider');
    final token = data['token']?.toString() ?? user['token']?.toString();

    await SessionService.saveUser(
      id: id,
      name: name,
      phone: _phone,
      token: token,
    );

    await FirebaseNotificationService().uploadFcmTokenToBackend(
      userId: id,
      role: 'user',
    );

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const UserHomeScreen()),
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
      role: 'user',
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
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        leading: _step != _AuthStep.phone
            ? BackButton(
                color: textColor,
                onPressed: () {
                  if (_step == _AuthStep.otp) {
                    _goTo(_AuthStep.phone);
                  } else {
                    _goTo(_AuthStep.otp);
                  }
                },
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header accent bar
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentStrong,
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
              const SizedBox(height: 32),

              // Step content
              if (_step == _AuthStep.phone) _buildPhoneStep(),
              if (_step == _AuthStep.otp) _buildOtpStep(subColor),
              if (_step == _AuthStep.register) _buildRegisterStep(),

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

              // Primary action button
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

  Widget _buildRegisterStep() => CustomTextField(
    hint: context.tr('fullName'),
    prefixIcon: Icons.person_outline,
    controller: _nameCtrl,
  );

  // ── Computed labels ───────────────────────────────────────────────────────

  String get _headerTitle {
    switch (_step) {
      case _AuthStep.phone:
        return context.tr('riderLogin');
      case _AuthStep.otp:
        return 'Verify OTP';
      case _AuthStep.register:
        return context.tr('riderSignUp');
    }
  }

  String get _headerSubtitle {
    switch (_step) {
      case _AuthStep.phone:
        return context.tr('userLoginSub');
      case _AuthStep.otp:
        return 'Enter the OTP sent to your phone via notification.';
      case _AuthStep.register:
        return 'Almost done! Tell us your name.';
    }
  }

  String get _buttonLabel {
    switch (_step) {
      case _AuthStep.phone:
        return 'Send OTP';
      case _AuthStep.otp:
        return 'Verify OTP';
      case _AuthStep.register:
        return context.tr('signUp');
    }
  }

  VoidCallback get _onPrimaryAction {
    switch (_step) {
      case _AuthStep.phone:
        return _sendOtp;
      case _AuthStep.otp:
        return _verifyOtp;
      case _AuthStep.register:
        return _completeProfile;
    }
  }
}
