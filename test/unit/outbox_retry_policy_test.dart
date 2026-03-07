import 'package:chatify/core/utils/outbox_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry delay grows exponentially and is capped', () {
    expect(
      OutboxRetryPolicy.nextDelay(retryCount: 0),
      const Duration(seconds: 2),
    );
    expect(
      OutboxRetryPolicy.nextDelay(retryCount: 1),
      const Duration(seconds: 4),
    );
    expect(
      OutboxRetryPolicy.nextDelay(retryCount: 2),
      const Duration(seconds: 8),
    );
    expect(
      OutboxRetryPolicy.nextDelay(retryCount: 20),
      const Duration(minutes: 15),
    );
  });
}
