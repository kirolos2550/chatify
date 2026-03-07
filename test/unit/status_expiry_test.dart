import 'package:chatify/core/utils/status_expiry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status expires after exactly 24 hours', () {
    final createdAt = DateTime.utc(2026, 3, 4, 10, 0, 0);
    final expiresAt = StatusExpiry.buildExpiry(createdAt);
    expect(expiresAt.difference(createdAt), const Duration(hours: 24));
  });
}
