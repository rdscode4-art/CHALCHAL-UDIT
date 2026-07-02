import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/device_utils.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/category_vehicle_image.dart';
import '../../../core/localization/app_localizations.dart';
import 'driver_trips_history_screen.dart';
import 'driver_complaint_screen.dart';
import 'driver_help_center_screen.dart';
import 'driver_about_screen.dart';
import 'driver_privacy_policy_screen.dart';
import 'driver_terms_screen.dart';
import '../../../widgets/driver/subscription_card_widget.dart';
import '../../../widgets/driver/subscription_plans_bottom_sheet.dart';
import '../../../services/subscription_service.dart';
import 'driver_edit_profile_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  final bool isOnline;
  final ValueChanged<bool> onOnlineToggle;
  final VoidCallback onLogout;

  const DriverProfileScreen({
    super.key,
    required this.isOnline,
    required this.onOnlineToggle,
    required this.onLogout,
  });

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  String _driverName = '';
  String _driverPhone = '';
  String _driverId = '';
  String _driverEmail = '-';
  String _avatarUrl = '';
  String _vehicleNumber = '-';
  String _vehicleType = '-';
  String _vehicleModel = '-';
  String _vehicleColor = '-';
  String _drivingLicense = '-';
  String _rcStatus = '-';
  String _insuranceStatus = '-';
  String _pollutionStatus = '-';
  String _verificationStatus = 'pending';
  bool _isLoadingProfile = true;
  bool _isDeleting = false;
  bool _isUploadingPhoto = false;
  final _subscriptionService = SubscriptionService.instance;
  String _deviceInfo = 'Loading...';

  @override
  void initState() {
    super.initState();
    _subscriptionService.addListener(_onSubscriptionChanged);
    _loadDriverData();
    _loadDeviceInfo();
    _subscriptionService.fetchSubscription();
  }

  Future<void> _loadDeviceInfo() async {
    final info = await DeviceUtils.getDeviceInfo();
    if (mounted) setState(() => _deviceInfo = info);
  }

  @override
  void dispose() {
    _subscriptionService.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  void _onSubscriptionChanged() {
    if (mounted) setState(() {});
  }

  void _showLanguageSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr('english')),
              trailing:
                  LanguageManager.localeNotifier.value.languageCode == 'en'
                  ? const Icon(Icons.check, color: AppColors.accentStrong)
                  : null,
              onTap: () {
                LanguageManager.setLocale(const Locale('en'));
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
            ListTile(
              title: Text(context.tr('hindi')),
              trailing:
                  LanguageManager.localeNotifier.value.languageCode == 'hi'
                  ? const Icon(Icons.check, color: AppColors.accentStrong)
                  : null,
              onTap: () {
                LanguageManager.setLocale(const Locale('hi'));
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  String _docStatus(Map<String, dynamic> data, List<String> urlKeys) {
    return _pickString(data, urlKeys).isNotEmpty ? 'Uploaded' : 'Not uploaded';
  }

  String _formatVerificationStatus(String raw) {
    final status = raw.toLowerCase();
    if (status == 'approved') return 'Verified';
    if (status.isEmpty) return 'Pending';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  void _applySessionDefaults(Map<String, String> session) {
    _driverName = session['name']?.isNotEmpty == true
        ? session['name']!
        : 'Driver';
    _driverPhone = session['phone']?.isNotEmpty == true
        ? session['phone']!
        : '-';
    _driverId = session['id'] ?? '';
    _vehicleNumber = session['vehicleNumber']?.isNotEmpty == true
        ? session['vehicleNumber']!
        : '-';
    _vehicleType = session['vehicleType']?.isNotEmpty == true
        ? session['vehicleType']!
        : '-';
    _vehicleModel = session['vehicleModel']?.isNotEmpty == true
        ? session['vehicleModel']!
        : '-';
    _vehicleColor = session['vehicleColor']?.isNotEmpty == true
        ? session['vehicleColor']!
        : '-';
    _verificationStatus = _formatVerificationStatus(
      session['verificationStatus'] ?? 'pending',
    );
  }

  void _applyProfileFromApi(Map<String, dynamic> profile) {
    final id = _pickString(profile, ['id', '_id', 'driverId']);
    if (id.isNotEmpty) _driverId = id;

    final name = _pickString(profile, ['name']);
    if (name.isNotEmpty) _driverName = name;

    final phone = _pickString(profile, ['phone']);
    if (phone.isNotEmpty) _driverPhone = phone;

    final email = _pickString(profile, ['email']);
    _driverEmail = email.isNotEmpty ? email : '-';

    _avatarUrl = _normalizePhotoUrl(
      _pickString(profile, ['profilePhotoUrl', 'profilePic', 'profilePhoto']),
    );

    final vehicleNumber = _pickString(profile, ['vehicleNumber']);
    if (vehicleNumber.isNotEmpty) _vehicleNumber = vehicleNumber;

    final vehicleType = _pickString(profile, ['vehicleType']);
    if (vehicleType.isNotEmpty) _vehicleType = vehicleType;

    final vehicleModel = _pickString(profile, ['vehicleModel', 'vehicle']);
    if (vehicleModel.isNotEmpty) _vehicleModel = vehicleModel;

    final vehicleColor = _pickString(profile, ['vehicleColor', 'color']);
    _vehicleColor = vehicleColor.isNotEmpty ? vehicleColor : '-';

    final licenseNo = _pickString(profile, [
      'drivingLicenseNumber',
      'licenseNumber',
      'drivingLicense',
    ]);
    _drivingLicense = licenseNo.isNotEmpty
        ? licenseNo
        : _docStatus(profile, [
            'drivingLicensePhotoFront',
            'drivingLicensePhoto',
            'licensePic',
            'licensePhoto',
          ]);

    _rcStatus = _docStatus(profile, ['rcPhoto', 'rcPic', 'rcDocument']);
    _insuranceStatus = _docStatus(profile, [
      'insurancePhoto',
      'insurancePic',
      'insuranceDocument',
    ]);
    _pollutionStatus = _docStatus(profile, [
      'pucPhoto',
      'pucPic',
      'pollutionCertificate',
      'pollutionCertificatePhoto',
    ]);

    final rawStatus = _pickString(profile, [
      'verificationStatus',
      'documentStatus',
      'status',
    ]);
    if (rawStatus.isNotEmpty) {
      _verificationStatus = _formatVerificationStatus(rawStatus);
    }
  }

  Future<void> _loadDriverData() async {
    final session = await SessionService.getSession();
    if (!mounted) return;

    setState(() {
      _applySessionDefaults(session);
      _isLoadingProfile = true;
    });

    if (_driverId.isEmpty) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }

    final res = await ApiService.getDriverProfile(_driverId);
    if (!mounted) return;

    if (res.success) {
      final raw = res.data;
      final profile = (raw['driver'] is Map<String, dynamic>)
          ? raw['driver'] as Map<String, dynamic>
          : raw;

      setState(() {
        _applyProfileFromApi(profile);
        _isLoadingProfile = false;
      });

      await SessionService.saveDriver(
        id: _driverId,
        name: _driverName,
        phone: _driverPhone,
        vehicleNumber: _vehicleNumber == '-' ? '' : _vehicleNumber,
        vehicleType: _vehicleType == '-' ? 'Auto' : _vehicleType,
        verificationStatus: _verificationStatus.toLowerCase(),
        vehicleModel: _vehicleModel == '-' ? '' : _vehicleModel,
        vehicleColor: _vehicleColor == '-' ? '' : _vehicleColor,
      );
    } else {
      setState(() => _isLoadingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('loadProfileError')),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  Future<void> _navigateToEditProfile() async {
    if (_driverId.isEmpty) return;
    
    // Pass current data to prefill
    final initialData = <String, dynamic>{
      'id': _driverId,
      'name': _driverName,
      'phone': _driverPhone,
      'email': _driverEmail,
      'vehicleNumber': _vehicleNumber,
      'vehicleType': _vehicleType,
      'vehicleModel': _vehicleModel,
      'drivingLicenseNumber': _drivingLicense,
    };

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverEditProfileScreen(initialData: initialData),
      ),
    );

    if (result == true) {
      _loadDriverData();
    }
  }

  // ── Photo URL normalization ──────────────────────────────────────────────
  String _normalizePhotoUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/$'), '');
    String pathStr = url;
    if (!pathStr.startsWith('/')) {
      pathStr = '/$pathStr';
    }
    if (!pathStr.startsWith('/uploads/drivers/')) {
      pathStr = '/uploads/drivers$pathStr';
    }
    return '$base$pathStr';
  }

  // ── Avatar tap ───────────────────────────────────────────────────────────
  void _onAvatarTap() {
    if (_avatarUrl.isNotEmpty) {
      _showPhotoOptions();
    } else {
      _pickAndUpload();
    }
  }

  void _showPhotoOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textCol = isDark ? AppColors.darkOnSurface : AppColors.textDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.accentStrong,
                ),
                title: Text(
                  context.tr('viewPhoto'),
                  style: AppTextStyles.body.copyWith(
                    color: textCol,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _viewFullPhoto();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.accentStrong,
                ),
                title: Text(
                  context.tr('changePhoto'),
                  style: AppTextStyles.body.copyWith(
                    color: textCol,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload();
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _viewFullPhoto() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DriverFullScreenPhoto(
          imageUrl: _avatarUrl,
          driverName: _driverName,
          onChangeTap: () {
            Navigator.pop(context);
            _pickAndUpload();
          },
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);

      final res = await ApiService.uploadDriverProfilePhoto(
        driverId: _driverId,
        name: _driverName,
        filePath: picked.path,
      );

      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);

      if (res.success) {
        final raw =
            res.data['profilePhotoUrl']?.toString() ??
            res.data['profilePic']?.toString() ??
            res.data['profilePhoto']?.toString() ??
            res.data['driver']?['profilePhotoUrl']?.toString() ??
            res.data['driver']?['profilePic']?.toString() ??
            '';
        final newUrl = _normalizePhotoUrl(raw);
        debugPrint('📸 [Driver] newAvatarUrl=$newUrl raw=$raw');

        if (newUrl.isNotEmpty) setState(() => _avatarUrl = newUrl);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('profilePhotoSuccess')),
            backgroundColor: AppColors.secondary,
          ),
        );
        _loadDriverData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('uploadFailed')}${res.errorMessage ?? ""}',
            ),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('galleryError')),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('deleteAccountConfirmTitle')),
        content: Text(context.tr('deleteAccountConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accentRed),
            child: Text(context.tr('submitRequest')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    final res = await ApiService.deleteDriverAccount(_driverId);
    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('deletionRequestSubmitted')),
          backgroundColor: AppColors.secondary,
        ),
      );
      widget.onLogout();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.tr('failedSubmitRequest')}${res.errorMessage ?? ""}',
          ),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: isDark
              ? AppColors.textLight.withValues(alpha: 0.5)
              : AppColors.textGrey,
        ),
      ),
    );
  }

  Widget _buildRowItem({
    required IconData icon,
    required String label,
    String? subtext,
    Color? textColor,
    Widget? trailingWidget,
    bool showDivider = true,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol =
        textColor ?? (isDark ? AppColors.darkOnSurface : AppColors.textDark);
    final iconCol = textColor ?? AppColors.accentStrong;

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: (isDark ? AppColors.darkBorder : AppColors.border)
                      .withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            )
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Icon(icon, color: iconCol, size: 22),
        title: Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: textCol,
          ),
        ),
        subtitle: subtext != null
            ? Text(
                subtext,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textLight.withValues(alpha: 0.6)
                      : AppColors.textGrey,
                ),
              )
            : null,
        trailing:
            trailingWidget ??
            (readOnly
                ? null
                : Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? AppColors.textLight.withValues(alpha: 0.4)
                        : AppColors.textGrey.withValues(alpha: 0.6),
                    size: 22,
                  )),
        onTap: readOnly ? null : onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textCol = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subTextCol = isDark
        ? AppColors.textLight.withValues(alpha: 0.6)
        : AppColors.textGrey;

    if (_isLoadingProfile || _isDeleting) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accentStrong),
        ),
      );
    }

    return SafeArea(
      child: Center(
        child: SizedBox(
          width: 400,
          child: RefreshIndicator(
            color: AppColors.accentStrong,
            onRefresh: _loadDriverData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                top: 24,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.all(16),
                    color: surface,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _onAvatarTap,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 35,
                                backgroundColor: AppColors.accentStrong,
                                backgroundImage: _avatarUrl.isNotEmpty
                                    ? NetworkImage(_avatarUrl)
                                    : null,
                                child: _isUploadingPhoto
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : _avatarUrl.isEmpty
                                    ? Text(
                                        _driverName.isNotEmpty
                                            ? _driverName
                                                  .split(' ')
                                                  .map(
                                                    (s) => s.isNotEmpty
                                                        ? s[0]
                                                        : '',
                                                  )
                                                  .take(2)
                                                  .join()
                                            : 'D',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 22,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentStrong,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverName,
                                style: AppTextStyles.heading.copyWith(
                                  fontSize: 20,
                                  color: textCol,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _driverPhone,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 14,
                                  color: subTextCol,
                                ),
                              ),
                              if (_driverId.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Driver ID: $_driverId',
                                  style: AppTextStyles.body.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: subTextCol.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, color: subTextCol),
                          onPressed: _navigateToEditProfile,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildSectionHeader(context.tr('basicInformation')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.portrait_rounded,
                          label: context.tr('profilePhoto'),
                          subtext: _avatarUrl.isNotEmpty
                              ? context.tr('tapToViewOrChange')
                              : context.tr('tapToUpload'),
                          onTap: _onAvatarTap,
                        ),
                        _buildRowItem(
                          icon: Icons.person_outline_rounded,
                          label: context.tr('fullName'),
                          subtext: _driverName,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.phone_android_rounded,
                          label: context.tr('phone'),
                          subtext: _driverPhone,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.mail_outline_rounded,
                          label: context.tr('email'),
                          subtext: _driverEmail,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.badge_outlined,
                          label: context.tr('driverId'),
                          subtext: _driverId.isNotEmpty ? _driverId : '-',
                          showDivider: true,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.language_rounded,
                          label: context.tr('language'),
                          subtext:
                              LanguageManager
                                      .localeNotifier
                                      .value
                                      .languageCode ==
                                  'hi'
                              ? context.tr('hindi')
                              : context.tr('english'),
                          showDivider: true,
                          onTap: () => _showLanguageSelectionDialog(context),
                        ),
                        _buildRowItem(
                          icon: Icons.smartphone_rounded,
                          label: 'Current Device',
                          subtext: _deviceInfo,
                          showDivider: false,
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader(context.tr('onlineStatus')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.online_prediction_rounded,
                          label: context.tr('goOnlineOfflineToggle'),
                          showDivider: false,
                          trailingWidget: Switch(
                            value: widget.isOnline,
                            activeThumbColor: AppColors.accentStrong,
                            activeTrackColor: AppColors.accentStrong.withValues(
                              alpha: 0.5,
                            ),
                            onChanged: widget.onOnlineToggle,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader(context.tr('vehicleInformation')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        // Vehicle Type row with category image
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withAlpha(20),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CategoryVehicleImage(
                                    vehicleType: _vehicleType,
                                    size: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('vehicleType'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _vehicleType,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        _buildRowItem(
                          icon: Icons.pin_outlined,
                          label: context.tr('vehicleNumber'),
                          subtext: _vehicleNumber,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.model_training_outlined,
                          label: context.tr('vehicleModel'),
                          subtext: _vehicleModel,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.color_lens_outlined,
                          label: context.tr('vehicleColor'),
                          subtext: _vehicleColor,
                          showDivider: false,
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader(context.tr('documentStatus')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.description_outlined,
                          label: context.tr('drivingLicense'),
                          subtext: _drivingLicense,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.receipt_outlined,
                          label: context.tr('rcDoc'),
                          subtext: _rcStatus,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.security_outlined,
                          label: context.tr('insuranceDoc'),
                          subtext: _insuranceStatus,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.co2_outlined,
                          label: context.tr('pucDoc'),
                          subtext: _pollutionStatus,
                          readOnly: true,
                        ),
                        _buildRowItem(
                          icon: Icons.verified_user_outlined,
                          label: context.tr('verificationStatus'),
                          subtext: _verificationStatus.toUpperCase(),
                          showDivider: false,
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader('KM Subscription'),
                  SubscriptionCardWidget(
                    onActionPressed: () =>
                        SubscriptionPlansBottomSheet.show(context),
                  ),

                  _buildSectionHeader(context.tr('rideSection')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.history_rounded,
                          label: context.tr('tripHistory'),
                          subtext: context.tr('completedCancelled'),
                          showDivider: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverTripsHistoryScreen(
                                  tripHistory: [],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader(context.tr('supportSafety')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.report_gmailerrorred_outlined,
                          label: context.tr('complaint'),
                          onTap: () {
                            if (_driverId.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.tr('pleaseSignInComplaint'),
                                  ),
                                  backgroundColor: AppColors.accentRed,
                                ),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DriverComplaintScreen(driverId: _driverId),
                              ),
                            );
                          },
                        ),
                        _buildRowItem(
                          icon: Icons.help_center_outlined,
                          label: context.tr('helpCenter'),
                          showDivider: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverHelpCenterScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader(context.tr('other')),
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    color: surface,
                    child: Column(
                      children: [
                        _buildRowItem(
                          icon: Icons.info_outline_rounded,
                          label: context.tr('aboutUs'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverAboutScreen(),
                              ),
                            );
                          },
                        ),
                        _buildRowItem(
                          icon: Icons.lock_outline_rounded,
                          label: context.tr('privacyPolicy'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const DriverPrivacyPolicyScreen(),
                              ),
                            );
                          },
                        ),
                        _buildRowItem(
                          icon: Icons.article_outlined,
                          label: context.tr('termsConditions'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverTermsScreen(),
                              ),
                            );
                          },
                        ),
                        _buildRowItem(
                          icon: Icons.logout_rounded,
                          label: context.tr('logout'),
                          textColor: AppColors.accentYellow,
                          onTap: widget.onLogout,
                        ),
                        _buildRowItem(
                          icon: Icons.delete_forever_rounded,
                          label: context.tr('deleteAccount'),
                          textColor: AppColors.accentRed,
                          showDivider: false,
                          onTap: _handleDeleteAccount,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Full-Screen Photo Viewer ─────────────────────────────────────────────────

class _DriverFullScreenPhoto extends StatelessWidget {
  final String imageUrl;
  final String driverName;
  final VoidCallback onChangeTap;

  const _DriverFullScreenPhoto({
    required this.imageUrl,
    required this.driverName,
    required this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          driverName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton.icon(
            onPressed: onChangeTap,
            icon: const Icon(Icons.edit, color: Colors.white, size: 18),
            label: Text(
              context.tr('change'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(
                color: AppColors.accentStrong,
              );
            },
            errorBuilder: (_, error, _) {
              debugPrint(
                'ERROR [DriverPhoto] Failed to load: $imageUrl — $error',
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('couldNotLoadPhoto'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
