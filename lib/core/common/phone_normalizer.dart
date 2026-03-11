class PhoneNormalizationResult {
  const PhoneNormalizationResult({
    required this.raw,
    required this.normalizedE164,
    required this.digits,
  });

  final String raw;
  final String normalizedE164;
  final String digits;

  bool get hasAnyValue => normalizedE164.isNotEmpty || digits.isNotEmpty;
}

abstract final class PhoneNormalizer {
  static PhoneNormalizationResult normalize(String raw) {
    final trimmed = raw.trim();
    final digits = toDigits(raw);
    return PhoneNormalizationResult(
      raw: trimmed,
      normalizedE164: toE164(raw),
      digits: digits,
    );
  }

  static String toDigits(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String toE164(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (value.startsWith('00')) {
      value = '+${value.substring(2)}';
    }

    if (value.startsWith('+')) {
      final digits = toDigits(value);
      if (digits.length < 8 || digits.length > 15) {
        return '';
      }
      return '+$digits';
    }

    final digits = toDigits(value);
    if (digits.length >= 8 && digits.length <= 15 && !value.startsWith('0')) {
      return '+$digits';
    }

    return '';
  }
}
