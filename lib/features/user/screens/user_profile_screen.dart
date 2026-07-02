import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/localization/app_localizations.dart';
import 'help_support_screen.dart';
import 'about_us_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import 'complaint_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final ValueChanged<int>? onTabChanged;

  const UserProfileScreen({
    super.key,
    required this.onLogout,
    this.onTabChanged,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String _userName = '';
  String _userPhone = '';
  String _userId = '';
  String _userEmail = '';
  String _avatarUrl = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
              trailing: LanguageManager.localeNotifier.value.languageCode == 'en'
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
              trailing: LanguageManager.localeNotifier.value.languageCode == 'hi'
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

  /// Normalize a photo URL — prepend baseUrl if it's a relative path.
  String _normalizePhotoUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    // Relative path like "/uploads/photo.jpg"
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/$'), '');
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  Future<void> _loadUserData() async {
    final session = await SessionService.getSession();
    if (mounted) {
      setState(() {
        _userName = session['name'] ?? 'Guest User';
        _userPhone = session['phone'] ?? '—';
        _userId = session['id'] ?? '';
        final normalizedName = _userName.toLowerCase().replaceAll(' ', '');
        _userEmail = normalizedName.isNotEmpty
            ? '$normalizedName@gmail.com'
            : 'user@example.com';
      });
    }

    if (_userId.isNotEmpty) {
      final res = await ApiService.getUserProfile(_userId);
      if (res.success && mounted) {
        final profile = res.data;
        final name = profile['name']?.toString() ?? _userName;
        final phone = profile['phone']?.toString() ?? _userPhone;
        final email = profile['email']?.toString() ?? '';
        final avatar =
            profile['profilePhotoUrl']?.toString() ??
            profile['profilePic']?.toString() ??
            '';

        setState(() {
          _userName = name;
          _userPhone = phone;
          _avatarUrl = _normalizePhotoUrl(avatar);
          if (email.isNotEmpty) {
            _userEmail = email;
          }
        });
        debugPrint('👤 [Profile] avatarUrl=$_avatarUrl');

        // Update local session cache
        await SessionService.saveUser(id: _userId, name: name, phone: phone);
      }
    }
  }

  /// Show full-screen photo viewer if photo exists, otherwise open picker.
  void _onAvatarTap() {
    if (_avatarUrl.isNotEmpty) {
      _showPhotoOptions();
    } else {
      _pickAndUpload();
    }
  }

  /// Bottom sheet: View Photo / Change Photo.
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
                  'View Photo',
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
                  Icons.edit_outlined,
                  color: AppColors.accentStrong,
                ),
                title: Text(
                  'Change Photo',
                  style: AppTextStyles.body.copyWith(
                    color: textCol,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showImageSourceSheet();
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-screen photo viewer.
  void _viewFullPhoto() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenPhoto(
          imageUrl: _avatarUrl,
          userName: _userName,
          onChangeTap: () {
            Navigator.pop(context);
            _showImageSourceSheet();
          },
        ),
      ),
    );
  }

  /// Bottom sheet: choose Gallery or Camera.
  void _showImageSourceSheet() {
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
              Text(
                'Choose Photo',
                style: AppTextStyles.subtitle.copyWith(
                  color: textCol,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.accentStrong,
                ),
                title: Text(
                  'Choose from Gallery',
                  style: AppTextStyles.body.copyWith(
                    color: textCol,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(source: ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.accentStrong,
                ),
                title: Text(
                  'Take a Photo',
                  style: AppTextStyles.body.copyWith(
                    color: textCol,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(source: ImageSource.camera);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (picked == null) return;

      setState(() => _isLoading = true);

      final res = await ApiService.uploadUserProfilePhoto(
        userId: _userId,
        name: _userName,
        filePath: picked.path,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res.success) {
        final newAvatarUrl = _normalizePhotoUrl(
          res.data['profilePhotoUrl']?.toString() ??
              res.data['profilePic']?.toString() ??
              res.data['user']?['profilePhotoUrl']?.toString() ??
              res.data['user']?['profilePic']?.toString() ??
              '',
        );
        debugPrint(
          '👤 [Upload] newAvatarUrl=$newAvatarUrl rawData=${res.data}',
        );

        setState(() {
          if (newAvatarUrl.isNotEmpty) _avatarUrl = newAvatarUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully.'),
            backgroundColor: AppColors.secondary,
          ),
        );

        _loadUserData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${res.errorMessage}'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open gallery. Please try again.'),
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
        title: const Text('Delete Account?'),
        content: const Text(
          'Are you sure you want to submit an account deletion request? '
          'Your account will be reviewed and deleted by our team.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accentRed),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    final res = await ApiService.deleteUserAccount(_userId);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Deletion request submitted. Your account will be deleted shortly.',
          ),
          backgroundColor: AppColors.secondary,
        ),
      );
      widget.onLogout();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit request: ${res.errorMessage}'),
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
    bool showDivider = true,
    required VoidCallback onTap,
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
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isDark
              ? AppColors.textLight.withValues(alpha: 0.4)
              : AppColors.textGrey.withValues(alpha: 0.6),
          size: 22,
        ),
        onTap: onTap,
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

    return SafeArea(
      child: Center(
        child: SizedBox(
          width:
              400, // expanded from 375 for standard/larger smartphone layouts
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accentStrong,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: 24,
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header card
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
                                    child: _avatarUrl.isEmpty
                                        ? Text(
                                            _userName.isNotEmpty
                                                ? _userName
                                                      .split(' ')
                                                      .map(
                                                        (s) => s.isNotEmpty
                                                            ? s[0]
                                                            : '',
                                                      )
                                                      .take(2)
                                                      .join()
                                                : 'U',
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
                                    _userName,
                                    style: AppTextStyles.heading.copyWith(
                                      fontSize: 20,
                                      color: textCol,
                                    ), // increased from 18
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userPhone,
                                    style: AppTextStyles.body.copyWith(
                                      fontSize: 14,
                                      color: subTextCol,
                                    ), // increased from 13
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // BASIC INFORMATION
                      _buildSectionHeader('Basic Information'),
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
                              label: 'Profile photo',
                              onTap: _onAvatarTap,
                            ),
                            _buildRowItem(
                              icon: Icons.person_outline_rounded,
                              label: 'Full name',
                              subtext: _userName,
                              onTap: () {},
                            ),
                            _buildRowItem(
                              icon: Icons.phone_android_rounded,
                              label: context.tr('phone'),
                              subtext: _userPhone,
                              onTap: () {},
                            ),
                            _buildRowItem(
                              icon: Icons.mail_outline_rounded,
                              label: context.tr('email'),
                              subtext: _userEmail,
                              showDivider: true,
                              onTap: () {},
                            ),
                            _buildRowItem(
                              icon: Icons.language_rounded,
                              label: context.tr('language'),
                              subtext: LanguageManager.localeNotifier.value.languageCode == 'hi'
                                  ? context.tr('hindi')
                                  : context.tr('english'),
                              showDivider: false,
                              onTap: () => _showLanguageSelectionDialog(context),
                            ),
                          ],
                        ),
                      ),

                      // RIDE SECTION
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
                              label: context.tr('rideHistory'),
                              subtext: '${context.tr('completed')} · ${context.tr('cancelled')}',
                              showDivider: false,
                              onTap: () {
                                widget.onTabChanged?.call(1);
                              },
                            ),
                          ],
                        ),
                      ),

                      // SAFETY & SUPPORT
                      _buildSectionHeader('Safety & Support'),
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
                              icon: Icons.help_outline_rounded,
                              label: 'Help & support',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HelpSupportScreen(),
                                ),
                              ),
                            ),
                            _buildRowItem(
                              icon: Icons.report_problem_outlined,
                              label: 'Complaint',
                              showDivider: false,
                              onTap: () {
                                if (_userId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please sign in to submit a complaint.',
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
                                        ComplaintScreen(userId: _userId),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // OTHER
                      _buildSectionHeader('Other'),
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
                              label: 'About us',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutUsScreen(),
                                ),
                              ),
                            ),
                            _buildRowItem(
                              icon: Icons.lock_outline_rounded,
                              label: 'Privacy policy',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                            ),
                            _buildRowItem(
                              icon: Icons.article_outlined,
                              label: 'Terms & conditions',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsConditionsScreen(),
                                ),
                              ),
                            ),
                            _buildRowItem(
                              icon: Icons.logout_rounded,
                              label: 'Logout',
                              textColor: AppColors.accentYellow,
                              onTap: widget.onLogout,
                            ),
                            _buildRowItem(
                              icon: Icons.delete_forever_rounded,
                              label: 'Delete account',
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
    );
  }
}

// ── Full-Screen Photo Viewer ─────────────────────────────────────────────────

class _FullScreenPhoto extends StatelessWidget {
  final String imageUrl;
  final String userName;
  final VoidCallback onChangeTap;

  const _FullScreenPhoto({
    required this.imageUrl,
    required this.userName,
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
          userName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton.icon(
            onPressed: onChangeTap,
            icon: const Icon(Icons.edit, color: Colors.white, size: 18),
            label: const Text(
              'Change',
              style: TextStyle(color: Colors.white, fontSize: 14),
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
            errorBuilder: (_, _, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
                SizedBox(height: 12),
                Text(
                  'Could not load photo',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
