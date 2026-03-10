import 'package:chatify/core/common/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LogRedactor masks sensitive fields recursively', () {
    final sanitized = LogRedactor.sanitizeMetadata(<String, Object?>{
      'phone': '+201012345678',
      'token': 'abcdef123456',
      'payload': <String, Object?>{
        'messageBody': 'hello world',
        'safe': 'value',
      },
      'list': <Object?>[
        <String, Object?>{'verificationId': 'ver_123'},
        'raw',
      ],
    });

    expect(sanitized['phone'], isNot('+201012345678'));
    expect(sanitized['token'], isNot('abcdef123456'));
    expect(
      (sanitized['payload'] as Map<String, Object?>)['messageBody'],
      'hello world',
    );
    expect((sanitized['payload'] as Map<String, Object?>)['safe'], 'value');
    final list = sanitized['list'] as List<Object?>;
    expect(
      (list.first as Map<String, Object?>)['verificationId'],
      isNot('ver_123'),
    );
  });
}
