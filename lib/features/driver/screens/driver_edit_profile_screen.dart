import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../services/category_service.dart';

class DriverEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const DriverEditProfileScreen({
    super.key,
    required this.initialData,
  });

  @override
  State<DriverEditProfileScreen> createState() => _DriverEditProfileScreenState();
}

class _DriverEditProfileScreenState extends State<DriverEditProfileScreen> {
  bool _loading = false;
  String? _error;
  String _driverId = '';

  // Text Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _vehicleNoCtrl = TextEditingController();
  final _licenseNumberCtrl = TextEditingController();
  final _aadharNumberCtrl = TextEditingController();

  String _selectedVehicleType = 'auto';
  List<Map<String, String>> _vehicleCategories = const [
    {'key': 'bike', 'name': 'Bike'},
    {'key': 'auto', 'name': 'Auto'},
    {'key': 'ev', 'name': 'EV'},
    {'key': 'sedan', 'name': 'Sedan'},
    {'key': 'suv', 'name': 'SUV'},
  ];
  bool _loadingCategories = false;

  // File objects
  XFile? _profilePic;
  XFile? _licensePic;
  XFile? _aadharFrontPic;
  XFile? _aadharBackPic;
  XFile? _rcPic;
  XFile? _insurancePic;
  XFile? _pucPic;

  // File paths (for API compat)
  String _profilePicPath = '';
  String _licensePicPath = '';
  String _aadharFrontPicPath = '';
  String _aadharBackPicPath = '';
  String _rcPicPath = '';
  String _insurancePicPath = '';
  String _pucPicPath = '';

  // Network URLs for existing documents
  String _profilePicUrl = '';
  String _licensePicUrl = '';
  String _aadharFrontPicUrl = '';
  String _aadharBackPicUrl = '';
  String _rcPicUrl = '';
  String _insurancePicUrl = '';
  String _pucPicUrl = '';

  // Display Controllers for file names
  final _profilePicCtrl = TextEditingController();
  final _licensePicCtrl = TextEditingController();
  final _aadharFrontPicCtrl = TextEditingController();
  final _aadharBackPicCtrl = TextEditingController();
  final _rcPicCtrl = TextEditingController();
  final _insurancePicCtrl = TextEditingController();
  final _pucPicCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _prefillData();
    _fetchLatestProfile();
  }

  void _prefillData() {
    final d = widget.initialData;
    _driverId = _pickString(d, ['id', '_id', 'driverId']);
    _nameCtrl.text = _pickString(d, ['name']);
    _emailCtrl.text = _pickString(d, ['email']);
    _vehicleNoCtrl.text = _pickString(d, ['vehicleNumber']);
    _licenseNumberCtrl.text = _pickString(d, ['drivingLicenseNumber', 'licenseNumber', 'drivingLicense']);
    _aadharNumberCtrl.text = _pickString(d, ['aadharNumber']);
    
    final vt = _pickString(d, ['vehicleType']);
    if (vt.isNotEmpty) _selectedVehicleType = vt;

    _profilePicUrl = _pickString(d, ['profilePhotoUrl', 'profilePic', 'profilePhoto']);
    if (_profilePicUrl.isNotEmpty) _profilePicCtrl.text = 'Uploaded (Tap to change)';

    _licensePicUrl = _pickString(d, ['drivingLicensePhotoFront', 'drivingLicensePhoto', 'licensePic', 'licensePhoto']);
    if (_licensePicUrl.isNotEmpty) _licensePicCtrl.text = 'Uploaded (Tap to change)';

    _aadharFrontPicUrl = _pickString(d, ['aadharFrontPhoto', 'aadharFront']);
    if (_aadharFrontPicUrl.isNotEmpty) _aadharFrontPicCtrl.text = 'Uploaded (Tap to change)';

    _aadharBackPicUrl = _pickString(d, ['aadharBackPhoto', 'aadharBack']);
    if (_aadharBackPicUrl.isNotEmpty) _aadharBackPicCtrl.text = 'Uploaded (Tap to change)';

    _rcPicUrl = _pickString(d, ['rcPhoto', 'rcPic', 'rcDocument']);
    if (_rcPicUrl.isNotEmpty) _rcPicCtrl.text = 'Uploaded (Tap to change)';

    _insurancePicUrl = _pickString(d, ['insurancePhoto', 'insurancePic', 'insuranceDocument']);
    if (_insurancePicUrl.isNotEmpty) _insurancePicCtrl.text = 'Uploaded (Tap to change)';

    _pucPicUrl = _pickString(d, ['pucPhoto', 'pucPic', 'pollutionCertificate', 'pollutionCertificatePhoto']);
    if (_pucPicUrl.isNotEmpty) _pucPicCtrl.text = 'Uploaded (Tap to change)';
  }

  Future<void> _fetchLatestProfile() async {
    if (_driverId.isEmpty) {
      final session = await SessionService.getSession();
      _driverId = session['id'] ?? '';
    }
    if (_driverId.isEmpty) return;

    setState(() => _loading = true);
    final res = await ApiService.getDriverProfile(_driverId);
    if (!mounted) return;
    
    if (res.success) {
      final d = res.data['driver'] as Map<String, dynamic>? ?? res.data;
      _nameCtrl.text = _pickString(d, ['name']);
      _emailCtrl.text = _pickString(d, ['email']);
      _vehicleNoCtrl.text = _pickString(d, ['vehicleNumber']);
      _licenseNumberCtrl.text = _pickString(d, ['drivingLicenseNumber', 'licenseNumber', 'drivingLicense']);
      _aadharNumberCtrl.text = _pickString(d, ['aadharNumber']);
      
      final vt = _pickString(d, ['vehicleType']);
      if (vt.isNotEmpty && _vehicleCategories.any((c) => c['key'] == vt)) {
        _selectedVehicleType = vt;
      }
      
      _profilePicUrl = _pickString(d, ['profilePhotoUrl', 'profilePic', 'profilePhoto']);
      if (_profilePicUrl.isNotEmpty) _profilePicCtrl.text = 'Uploaded (Tap to change)';

      _licensePicUrl = _pickString(d, ['drivingLicensePhotoFront', 'drivingLicensePhoto', 'licensePic', 'licensePhoto']);
      if (_licensePicUrl.isNotEmpty) _licensePicCtrl.text = 'Uploaded (Tap to change)';

      _aadharFrontPicUrl = _pickString(d, ['aadharFrontPhoto', 'aadharFront']);
      if (_aadharFrontPicUrl.isNotEmpty) _aadharFrontPicCtrl.text = 'Uploaded (Tap to change)';

      _aadharBackPicUrl = _pickString(d, ['aadharBackPhoto', 'aadharBack']);
      if (_aadharBackPicUrl.isNotEmpty) _aadharBackPicCtrl.text = 'Uploaded (Tap to change)';

      _rcPicUrl = _pickString(d, ['rcPhoto', 'rcPic', 'rcDocument']);
      if (_rcPicUrl.isNotEmpty) _rcPicCtrl.text = 'Uploaded (Tap to change)';

      _insurancePicUrl = _pickString(d, ['insurancePhoto', 'insurancePic', 'insuranceDocument']);
      if (_insurancePicUrl.isNotEmpty) _insurancePicCtrl.text = 'Uploaded (Tap to change)';

      _pucPicUrl = _pickString(d, ['pucPhoto', 'pucPic', 'pollutionCertificate', 'pollutionCertificatePhoto']);
      if (_pucPicUrl.isNotEmpty) _pucPicCtrl.text = 'Uploaded (Tap to change)';
    }
    setState(() => _loading = false);
  }

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

  String _pickString(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty && value.toString().toLowerCase() != 'null') {
        return value.toString().trim();
      }
    }
    return '';
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final cats = await CategoryService.instance.fetchCategories(role: 'driver');
      if (!mounted || cats.isEmpty) return;
      final items = cats
          .map((c) => {'key': c.key, 'name': c.name})
          .where((m) => m['key']!.isNotEmpty)
          .toList();
      if (items.isEmpty) return;
      setState(() {
        _vehicleCategories = items;
        if (!items.any((m) => m['key'] == _selectedVehicleType)) {
          _selectedVehicleType = items.first['key']!;
        }
        _loadingCategories = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

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

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty || _vehicleNoCtrl.text.isEmpty) {
      setState(() => _error = 'Name and Vehicle Number are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await ApiService.updateDriverProfile(
      driverId: _driverId,
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      vehicleType: _selectedVehicleType,
      vehicleNumber: _vehicleNoCtrl.text.trim(),
      drivingLicenseNumber: _licenseNumberCtrl.text.trim(),
      aadharNumber: _aadharNumberCtrl.text.trim(),
      profilePhotoPath: _profilePicPath,
      profilePhotoXFile: _profilePic,
      drivingLicenseFrontPath: _licensePicPath,
      drivingLicenseFrontXFile: _licensePic,
      aadharFrontPath: _aadharFrontPicPath,
      aadharFrontXFile: _aadharFrontPic,
      aadharBackPath: _aadharBackPicPath,
      aadharBackXFile: _aadharBackPic,
      rcPhotoPath: _rcPicPath,
      rcPhotoXFile: _rcPic,
      insurancePhotoPath: _insurancePicPath,
      insurancePhotoXFile: _insurancePic,
      pucPhotoPath: _pucPicPath,
      pucPhotoXFile: _pucPic,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true); // Return true to signal refresh
    } else {
      setState(() => _error = res.errorMessage ?? 'Failed to update profile.');
    }
  }

  Widget _sectionLabel(String label, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildFileField(String hint, TextEditingController ctrl, XFile? xfile, String url, void Function() onPick) {
    Widget? prefixImage;
    if (xfile != null || url.isNotEmpty) {
      prefixImage = Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.surface,
          image: DecorationImage(
            image: xfile != null
                ? FileImage(File(xfile.path))
                : NetworkImage(_normalizePhotoUrl(url)) as ImageProvider,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomTextField(
        hint: hint,
        controller: ctrl,
        readOnly: true,
        prefixWidget: prefixImage,
        prefixIcon: prefixImage == null ? Icons.image_outlined : null,
        suffixIcon: Icons.upload_file,
        onTap: onPick,
        onSuffixTap: onPick,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Edit Profile', style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Personal Details', textColor),
              CustomTextField(
                hint: 'Full Name',
                controller: _nameCtrl,
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                hint: 'Email (Optional)',
                controller: _emailCtrl,
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                hint: 'Aadhar Number',
                controller: _aadharNumberCtrl,
                prefixIcon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 12),
              _sectionLabel('Vehicle Details', textColor),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceSoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: _loadingCategories
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Center(
                            child: SizedBox(
                                width: 24.0,
                                height: 24.0,
                                child: CircularProgressIndicator(strokeWidth: 2.0),
                            ),
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedVehicleType,
                          isExpanded: true,
                          dropdownColor: isDark ? AppColors.darkSurfaceSoft : AppColors.surface,
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.textGrey),
                          items: _vehicleCategories.map((cat) {
                            return DropdownMenuItem(
                              value: cat['key'],
                              child: Text(
                                cat['name']!,
                                style: TextStyle(color: textColor, fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedVehicleType = val);
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                hint: 'Vehicle Number (e.g. MH 01 AB 1234)',
                controller: _vehicleNoCtrl,
                prefixIcon: Icons.directions_car_outlined,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                hint: 'Driving License Number',
                controller: _licenseNumberCtrl,
                prefixIcon: Icons.card_membership_outlined,
              ),

              const SizedBox(height: 12),
              _sectionLabel('Documents (Select to update)', textColor),
              _buildFileField('Profile Photo', _profilePicCtrl, _profilePic, _profilePicUrl, () => _pickPhoto(onPicked: (f, d) {
                _profilePic = f; _profilePicPath = f.path; _profilePicCtrl.text = d;
              })),
              _buildFileField('Driving License Front', _licensePicCtrl, _licensePic, _licensePicUrl, () => _pickPhoto(onPicked: (f, d) {
                _licensePic = f; _licensePicPath = f.path; _licensePicCtrl.text = d;
              })),
              _buildFileField('Aadhar Front', _aadharFrontPicCtrl, _aadharFrontPic, _aadharFrontPicUrl, () => _pickPhoto(onPicked: (f, d) {
                _aadharFrontPic = f; _aadharFrontPicPath = f.path; _aadharFrontPicCtrl.text = d;
              })),
              _buildFileField('Aadhar Back', _aadharBackPicCtrl, _aadharBackPic, _aadharBackPicUrl, () => _pickPhoto(onPicked: (f, d) {
                _aadharBackPic = f; _aadharBackPicPath = f.path; _aadharBackPicCtrl.text = d;
              })),
              _buildFileField('RC Photo', _rcPicCtrl, _rcPic, _rcPicUrl, () => _pickPhoto(onPicked: (f, d) {
                _rcPic = f; _rcPicPath = f.path; _rcPicCtrl.text = d;
              })),
              _buildFileField('Insurance Photo', _insurancePicCtrl, _insurancePic, _insurancePicUrl, () => _pickPhoto(onPicked: (f, d) {
                _insurancePic = f; _insurancePicPath = f.path; _insurancePicCtrl.text = d;
              })),
              _buildFileField('PUC Photo', _pucPicCtrl, _pucPic, _pucPicUrl, () => _pickPhoto(onPicked: (f, d) {
                _pucPic = f; _pucPicPath = f.path; _pucPicCtrl.text = d;
              })),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.accentRed, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 13))),
                  ],
                ),
              ],
              
              const SizedBox(height: 32),
              _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentStrong))
                  : CustomButton(
                      label: 'Save Changes',
                      color: AppColors.accentStrong,
                      onPressed: _submit,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
