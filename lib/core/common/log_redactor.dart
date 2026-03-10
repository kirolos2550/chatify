import 'dart:convert';

abstract final class LogRedactor {
  static const List<String> _sensitiveKeyFragments = <String>[
    'phone',
    'token',
    'verification',
    'otp',
    'password',
    'secret',
    'bearer',
    'auth',
    'pin',
  ];

  static Map<String, Object?> sanitizeMetadata(Map<String, Object?> input) {
    final output = <String, Object?>{};
    input.forEach((key, value) {
      output[key] = _sanitizeValue(key, value);
    });
    return output;
  }

  static Object? sanitizeObject(Object? value, {String? keyHint}) {
    return _sanitizeValue(keyHint ?? 'value', value);
  }

  static bool isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    for (final fragment in _sensitiveKeyFragments) {
      if (normalized.contains(fragment)) {
        return true;
      }
    }
    return false;
  }

  static String toSafeJson(Map<String, Object?> metadata) {
    return jsonEncode(sanitizeMetadata(metadata));
  }

  static Object? _sanitizeValue(String key, Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      final nested = <String, Object?>{};
      value.forEach((nestedKey, nestedValue) {
        nested['$nestedKey'] = _sanitizeValue('$nestedKey', nestedValue);
      });
      return nested;
    }

    if (value is List) {
      return value.map((item) => _sanitizeValue(key, item)).toList();
    }

    final text = value.toString();
    if (isSensitiveKey(key)) {
      return _mask(text);
    }
    return _singleLine(text);
  }

  static String _mask(String raw) {
    final cleaned = _singleLine(raw);
    if (cleaned.isEmpty) {
      return '';
    }
    if (cleaned.length <= 4) {
      return '***';
    }
    final visibleTail = cleaned.substring(cleaned.length - 2);
    return '***$visibleTail';
  }

  static String _singleLine(String value) {
    return value.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
  }
}
