import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNormalizer.toE164', () {
    test('keeps valid E.164 as-is', () {
      expect(PhoneNormalizer.toE164('+201001234567'), '+201001234567');
    });

    test('converts 00-prefixed international number to E.164', () {
      expect(PhoneNormalizer.toE164('00201001234567'), '+201001234567');
    });

    test('converts plain international digits to E.164', () {
      expect(PhoneNormalizer.toE164('201001234567'), '+201001234567');
    });

    test('returns empty for local numbers without country code', () {
      expect(PhoneNormalizer.toE164('01001234567'), isEmpty);
    });
  });

  group('PhoneNormalizer.toDigits', () {
    test('strips symbols and keeps only digits', () {
      expect(PhoneNormalizer.toDigits('+20 (100) 123-4567'), '201001234567');
    });
  });

  test('normalize returns both e164 and digits fallback', () {
    final normalized = PhoneNormalizer.normalize('+201001234567');
    expect(normalized.normalizedE164, '+201001234567');
    expect(normalized.digits, '201001234567');
    expect(normalized.hasAnyValue, isTrue);
  });
}
