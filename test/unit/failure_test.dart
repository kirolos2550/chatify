import 'package:chatify/core/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Failure keeps backward-compatible message constructor', () {
    const failure = Failure('Simple failure');
    expect(failure.message, 'Simple failure');
    expect(failure.code, isNull);
    expect(failure.source, isNull);
  });

  test('Failure.fromException builds structured metadata', () {
    final stackTrace = StackTrace.current;
    final failure = Failure.fromException(
      Exception('boom'),
      stackTrace: stackTrace,
      code: 'boom_code',
      source: 'unit_test',
      operation: 'fromException',
      metadata: const <String, Object?>{'step': 1},
    );

    expect(failure.message, contains('boom'));
    expect(failure.code, 'boom_code');
    expect(failure.source, 'unit_test');
    expect(failure.operation, 'fromException');
    expect(failure.stackTrace, stackTrace);
    expect(failure.metadata?['step'], 1);
  });

  test('Failure.validation and Failure.network factories are populated', () {
    final validation = Failure.validation(
      'Invalid phone format',
      field: 'phone',
      operation: 'requestOtp',
    );
    final network = Failure.network(message: 'No internet', operation: 'sync');

    expect(validation.code, 'validation_error');
    expect(validation.metadata?['field'], 'phone');
    expect(network.code, 'network_error');
    expect(network.operation, 'sync');
  });
}
