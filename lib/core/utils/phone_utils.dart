/// True when [raw] is a 10-digit Indian mobile (optional +91 / leading 0).
bool isValidIndianMobile(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length == 12) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }
  return digits.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
}

/// Normalizes Indian mobile input to E.164 (+91XXXXXXXXXX).
String formatIndianPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length == 12) {
    return '+$digits';
  }
  if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }
  if (digits.length == 10) {
    return '+91$digits';
  }
  if (raw.trim().startsWith('+')) {
    return raw.trim();
  }
  return '+91$digits';
}

/// Normalizes Indian mobile input to exactly 10 digits (stripping any country code prefix or leading zero).
String get10DigitPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length == 12) {
    return digits.substring(2);
  }
  if (digits.startsWith('0') && digits.length == 11) {
    return digits.substring(1);
  }
  return digits;
}
