/// Normalizes plate input: uppercase, no spaces or hyphens.
String normalizeVehicleNumber(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

/// Standard Indian plates (e.g. DL01AB1234, DL1AB1234) and Bharat (BH) series.
bool isValidIndianVehicleNumber(String raw) {
  final plate = normalizeVehicleNumber(raw);
  if (plate.isEmpty) return false;

  const standard = r'^[A-Z]{2}\d{1,2}[A-Z]{1,3}\d{4}$';
  const bharat = r'^\d{2}BH\d{4}[A-Z]{2}$';

  return RegExp(standard).hasMatch(plate) || RegExp(bharat).hasMatch(plate);
}

bool looksLikeVehicleNumber(String raw) =>
    RegExp(r'[A-Za-z]').hasMatch(raw.trim());
