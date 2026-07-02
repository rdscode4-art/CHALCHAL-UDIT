import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';

enum _ComplaintType { general, driver }

class _CompletedRide {
  final String rideId;
  final String pickup;
  final String dropoff;
  final String driverName;
  final String driverId;
  final String vehicleNumber;
  final String date;
  final DateTime? completedAt;

  const _CompletedRide({
    required this.rideId,
    required this.pickup,
    required this.dropoff,
    required this.driverName,
    required this.driverId,
    required this.vehicleNumber,
    required this.date,
    this.completedAt,
  });
}

class ComplaintScreen extends StatefulWidget {
  final String userId;

  const ComplaintScreen({super.key, required this.userId});

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  _ComplaintType _complaintType = _ComplaintType.general;
  bool _isSubmitting = false;
  bool _loadingRides = false;
  bool _rideSelectionError = false;

  final _generalFormKey = GlobalKey<FormState>();
  final _driverFormKey = GlobalKey<FormState>();

  final _subjectController = TextEditingController();
  final _generalDescriptionController = TextEditingController();
  final _driverDescriptionController = TextEditingController();

  final _rideIdDisplayController = TextEditingController();
  final _driverNameDisplayController = TextEditingController();
  final _vehicleNumberDisplayController = TextEditingController();

  String? _selectedCategory;
  String? _selectedComplaintReason;
  _CompletedRide? _selectedRide;

  static const List<String> _categories = [
    'App Bug',
    'Payment Issue',
    'Booking Issue',
    'Login Problem',
    'Other',
  ];

  static const List<String> _driverReasons = [
    'Rash Driving',
    'Driver Misbehavior',
    'Wrong Fare',
    'Unsafe Driving',
    'Late Arrival',
    'Other',
  ];

  List<_CompletedRide> _rides = [];

  @override
  void initState() {
    super.initState();
    _loadRides();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _generalDescriptionController.dispose();
    _driverDescriptionController.dispose();
    _rideIdDisplayController.dispose();
    _driverNameDisplayController.dispose();
    _vehicleNumberDisplayController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  _CompletedRide? _parseRide(Map<String, dynamic> item) {
    final rideId =
        item['_id']?.toString() ??
        item['id']?.toString() ??
        item['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return null;

    final status = (item['status']?.toString() ?? '').toLowerCase();
    if (status.isNotEmpty &&
        status != 'completed' &&
        status != 'complete' &&
        status != 'finished') {
      return null;
    }

    final pickup =
        item['pickup']?.toString() ??
        item['pickupLocation']?.toString() ??
        'Pickup';
    final dropoff =
        item['destination']?.toString() ??
        item['dropoffLocation']?.toString() ??
        'Destination';

    final driverMap = (item['driver'] is Map<String, dynamic>)
        ? item['driver'] as Map<String, dynamic>
        : (item['driverId'] is Map<String, dynamic>)
        ? item['driverId'] as Map<String, dynamic>
        : (item['assignedDriverId'] is Map<String, dynamic>)
        ? item['assignedDriverId'] as Map<String, dynamic>
        : null;

    var driverName = driverMap?['name']?.toString() ?? 'Driver';
    if (driverName == 'Driver') {
      driverName = item['driverName']?.toString() ?? 'Driver';
    }

    var vehicleNumber =
        driverMap?['vehicleNumber']?.toString() ??
        driverMap?['vehicle']?.toString() ??
        '—';
    if (vehicleNumber == '—') {
      vehicleNumber =
          item['vehicleNumber']?.toString() ??
          item['vehicle']?.toString() ??
          '—';
    }

    var driverId =
        driverMap?['_id']?.toString() ?? driverMap?['id']?.toString();
    if (driverId == null || driverId.isEmpty) {
      final rawDriverId = item['driverId'] ?? item['assignedDriverId'];
      if (rawDriverId is String && rawDriverId.isNotEmpty) {
        driverId = rawDriverId;
      } else {
        driverId = rawDriverId?.toString() ?? '';
      }
    }
    debugPrint(
      '🚗 [parseRide] rideId=$rideId driverId=$driverId driverName=$driverName',
    );

    var dateStr = '—';
    DateTime? completedAt;
    final rawDate =
        item['date'] ??
        item['completedAt'] ??
        item['startedAt'] ??
        item['createdAt'];
    if (rawDate != null) {
      try {
        completedAt = DateTime.parse(rawDate.toString()).toLocal();
        dateStr = _formatDate(completedAt);
      } catch (_) {
        dateStr = rawDate.toString();
      }
    }

    return _CompletedRide(
      rideId: rideId,
      pickup: pickup,
      dropoff: dropoff,
      driverName: driverName,
      driverId: driverId,
      vehicleNumber: vehicleNumber,
      date: dateStr,
      completedAt: completedAt,
    );
  }

  Future<void> _loadRides() async {
    if (widget.userId.isEmpty) return;
    setState(() => _loadingRides = true);
    final res = await ApiService.getUserRides(widget.userId);
    if (!mounted) return;

    final rides = <_CompletedRide>[];
    if (res.success) {
      final list = res.data['rides'] as List<dynamic>? ?? [];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final ride = _parseRide(item);
        if (ride != null) rides.add(ride);
      }
    }

    rides.sort((a, b) {
      final aDate = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    final recentRides = rides.length > 3 ? rides.sublist(0, 3) : rides;

    setState(() {
      _rides = recentRides;
      _loadingRides = false;
      if (_selectedRide != null &&
          !recentRides.any((r) => r.rideId == _selectedRide!.rideId)) {
        _selectRide(null);
      }
    });
  }

  void _selectRide(_CompletedRide? ride) {
    setState(() {
      _selectedRide = ride;
      _rideSelectionError = false;
      _rideIdDisplayController.text = ride?.rideId ?? '';
      _driverNameDisplayController.text = ride?.driverName ?? '';
      _vehicleNumberDisplayController.text = ride?.vehicleNumber ?? '';
    });
  }

  Future<void> _submitGeneral() async {
    if (!_generalFormKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final res = await ApiService.submitGeneralComplaint(
      userId: widget.userId,
      subject: _subjectController.text.trim(),
      category: _selectedCategory!,
      description: _generalDescriptionController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res.success) {
      _showSuccess();
      _subjectController.clear();
      _generalDescriptionController.clear();
      setState(() => _selectedCategory = null);
    } else {
      _showError(res.errorMessage ?? 'Failed to submit complaint.');
    }
  }

  Future<void> _submitDriver() async {
    final rideValid = _selectedRide != null;
    setState(() => _rideSelectionError = !rideValid);

    if (!_driverFormKey.currentState!.validate() || !rideValid) return;

    final ride = _selectedRide!;

    setState(() => _isSubmitting = true);
    final res = await ApiService.submitDriverComplaint(
      userId: widget.userId,
      rideId: ride.rideId,
      reason: _selectedComplaintReason!,
      description: _driverDescriptionController.text.trim(),
      driverId: ride.driverId,
      driverName: ride.driverName,
      vehicleNumber: ride.vehicleNumber,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res.success) {
      _showSuccess();
      _driverDescriptionController.clear();
      setState(() => _selectedComplaintReason = null);
      _selectRide(null);
    } else {
      _showError(res.errorMessage ?? 'Failed to submit complaint.');
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Complaint submitted successfully.'),
        backgroundColor: AppColors.secondary,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.accentRed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffold = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final textSec = isDark
        ? AppColors.darkOnSurface.withAlpha(160)
        : AppColors.textGrey;
    final accent = AppColors.accentStrong;

    return Scaffold(
      backgroundColor: scaffold,
      appBar: AppBar(
        title: const Text('Complaint'),
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          Text(
            'Submit a complaint to our admin team.',
            style: AppTextStyles.body.copyWith(color: textSec, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _buildTypeSelector(surface, border, textPri, accent),
          const SizedBox(height: 24),
          if (_complaintType == _ComplaintType.general)
            _buildGeneralForm(surface, border, textPri, textSec, accent)
          else
            _buildDriverForm(surface, border, textPri, textSec, accent),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(
    Color surface,
    Color border,
    Color textPri,
    Color accent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _typeChip(
              label: 'General Complaint',
              selected: _complaintType == _ComplaintType.general,
              accent: accent,
              textPri: textPri,
              onTap: () =>
                  setState(() => _complaintType = _ComplaintType.general),
            ),
          ),
          Expanded(
            child: _typeChip(
              label: 'Driver Complaint',
              selected: _complaintType == _ComplaintType.driver,
              accent: accent,
              textPri: textPri,
              onTap: () =>
                  setState(() => _complaintType = _ComplaintType.driver),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip({
    required String label,
    required bool selected,
    required Color accent,
    required Color textPri,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : textPri,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralForm(
    Color surface,
    Color border,
    Color textPri,
    Color textSec,
    Color accent,
  ) {
    return Form(
      key: _generalFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('Subject', textSec),
          const SizedBox(height: 8),
          _textField(
            controller: _subjectController,
            hint: 'Brief summary of your issue',
            surface: surface,
            border: border,
            textPri: textPri,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
          ),
          const SizedBox(height: 18),
          _fieldLabel('Complaint Category', textSec),
          const SizedBox(height: 8),
          _dropdown<String>(
            value: _selectedCategory,
            hint: 'Select category',
            items: _categories,
            surface: surface,
            border: border,
            textPri: textPri,
            onChanged: (v) => setState(() => _selectedCategory = v),
            validator: () =>
                _selectedCategory == null ? 'Please select a category' : null,
          ),
          const SizedBox(height: 18),
          _fieldLabel('Description', textSec),
          const SizedBox(height: 8),
          _textField(
            controller: _generalDescriptionController,
            hint: 'Describe your issue in detail',
            surface: surface,
            border: border,
            textPri: textPri,
            maxLines: 5,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Description is required'
                : null,
          ),
          const SizedBox(height: 28),
          _submitButton(
            label: 'Submit Complaint',
            accent: accent,
            onPressed: _isSubmitting ? null : _submitGeneral,
          ),
        ],
      ),
    );
  }

  Widget _buildDriverForm(
    Color surface,
    Color border,
    Color textPri,
    Color textSec,
    Color accent,
  ) {
    return Form(
      key: _driverFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('Select Ride (Recent 3)', textSec),
          const SizedBox(height: 8),
          if (_loadingRides)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: AppColors.accentStrong),
              ),
            )
          else if (_rides.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Text(
                'No completed rides found. Complete a ride before filing a driver complaint.',
                style: AppTextStyles.body.copyWith(
                  color: textSec,
                  fontSize: 14,
                ),
              ),
            )
          else ...[
            ..._rides.map(
              (ride) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _rideHistoryCard(
                  ride: ride,
                  selected: _selectedRide?.rideId == ride.rideId,
                  surface: surface,
                  border: border,
                  textPri: textPri,
                  textSec: textSec,
                  accent: accent,
                  onTap: () => _selectRide(ride),
                ),
              ),
            ),
            if (_rideSelectionError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Please select a ride',
                  style: TextStyle(color: AppColors.accentRed, fontSize: 12),
                ),
              ),
          ],
          if (_selectedRide != null) ...[
            const SizedBox(height: 20),
            _fieldLabel('Driver Details', textSec),
            const SizedBox(height: 8),
            _readOnlyField(
              label: 'Ride ID',
              controller: _rideIdDisplayController,
              surface: surface,
              border: border,
              textPri: textPri,
              textSec: textSec,
            ),
            const SizedBox(height: 12),
            _readOnlyField(
              label: 'Driver Name',
              controller: _driverNameDisplayController,
              surface: surface,
              border: border,
              textPri: textPri,
              textSec: textSec,
            ),
            const SizedBox(height: 12),
            _readOnlyField(
              label: 'Vehicle Number',
              controller: _vehicleNumberDisplayController,
              surface: surface,
              border: border,
              textPri: textPri,
              textSec: textSec,
            ),
          ],
          const SizedBox(height: 20),
          _fieldLabel('Complaint Reason', textSec),
          const SizedBox(height: 8),
          _dropdown<String>(
            value: _selectedComplaintReason,
            hint: 'Select reason',
            items: _driverReasons,
            surface: surface,
            border: border,
            textPri: textPri,
            onChanged: (v) => setState(() => _selectedComplaintReason = v),
            validator: () => _selectedComplaintReason == null
                ? 'Please select a complaint reason'
                : null,
          ),
          const SizedBox(height: 18),
          _fieldLabel('Description', textSec),
          const SizedBox(height: 8),
          _textField(
            controller: _driverDescriptionController,
            hint: 'Describe the issue with the driver',
            surface: surface,
            border: border,
            textPri: textPri,
            maxLines: 5,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Description is required'
                : null,
          ),
          const SizedBox(height: 28),
          _submitButton(
            label: 'Submit Complaint',
            accent: accent,
            onPressed: (_isSubmitting || _rides.isEmpty) ? null : _submitDriver,
          ),
        ],
      ),
    );
  }

  Widget _rideHistoryCard({
    required _CompletedRide ride,
    required bool selected,
    required Color surface,
    required Color border,
    required Color textPri,
    required Color textSec,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : border,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ride ID: ${ride.rideId}',
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: accent, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              _rideDetailRow(
                Icons.trip_origin,
                'Pickup',
                ride.pickup,
                textPri,
                textSec,
              ),
              const SizedBox(height: 6),
              _rideDetailRow(
                Icons.location_on_outlined,
                'Drop',
                ride.dropoff,
                textPri,
                textSec,
              ),
              const SizedBox(height: 6),
              _rideDetailRow(
                Icons.person_outline,
                'Driver',
                ride.driverName,
                textPri,
                textSec,
              ),
              const SizedBox(height: 6),
              _rideDetailRow(
                Icons.directions_car_outlined,
                'Vehicle',
                ride.vehicleNumber,
                textPri,
                textSec,
              ),
              const SizedBox(height: 6),
              _rideDetailRow(
                Icons.calendar_today_outlined,
                'Date',
                ride.date,
                textPri,
                textSec,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rideDetailRow(
    IconData icon,
    String label,
    String value,
    Color textPri,
    Color textSec,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: textSec),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.body.copyWith(fontSize: 13, color: textPri),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(fontWeight: FontWeight.w600, color: textSec),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyField({
    required String label,
    required TextEditingController controller,
    required Color surface,
    required Color border,
    required Color textPri,
    required Color textSec,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textSec,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: true,
          style: AppTextStyles.body.copyWith(color: textPri, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: surface.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, Color color) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required Color surface,
    required Color border,
    required Color textPri,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: AppTextStyles.body.copyWith(color: textPri),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(
          color: textPri.withAlpha(120),
          fontSize: 14,
        ),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.accentStrong,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentRed),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required Color surface,
    required Color border,
    required Color textPri,
    required ValueChanged<T?> onChanged,
    required String? Function() validator,
  }) {
    return FormField<T>(
      initialValue: value,
      validator: (_) => validator(),
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: state.hasError ? AppColors.accentRed : border,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  hint: Text(
                    hint,
                    style: AppTextStyles.body.copyWith(
                      color: textPri.withAlpha(140),
                    ),
                  ),
                  items: items
                      .map(
                        (item) => DropdownMenuItem<T>(
                          value: item,
                          child: Text(
                            item.toString(),
                            style: AppTextStyles.body.copyWith(color: textPri),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    onChanged(v);
                    state.didChange(v);
                  },
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  state.errorText!,
                  style: const TextStyle(
                    color: AppColors.accentRed,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _submitButton({
    required String label,
    required Color accent,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withAlpha(120),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: AppTextStyles.button.copyWith(color: Colors.white),
              ),
      ),
    );
  }
}
