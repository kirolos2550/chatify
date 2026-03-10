class Failure {
  const Failure(
    this.message, {
    this.code,
    this.source,
    this.operation,
    this.cause,
    this.stackTrace,
    this.metadata,
  });

  final String message;
  final String? code;
  final String? source;
  final String? operation;
  final Object? cause;
  final StackTrace? stackTrace;
  final Map<String, Object?>? metadata;

  factory Failure.fromException(
    Object exception, {
    StackTrace? stackTrace,
    String? message,
    String? code,
    String? source,
    String? operation,
    Map<String, Object?>? metadata,
  }) {
    return Failure(
      message ?? _normalizeExceptionMessage(exception),
      code: code,
      source: source,
      operation: operation,
      cause: exception,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  factory Failure.validation(
    String message, {
    String? field,
    String? source,
    String? operation,
    Map<String, Object?>? metadata,
  }) {
    return Failure(
      message,
      code: 'validation_error',
      source: source ?? 'validation',
      operation: operation,
      metadata: <String, Object?>{'field': ?field, ...?metadata},
    );
  }

  factory Failure.unauthorized({
    String message = 'Unauthorized',
    String? source,
    String? operation,
    Map<String, Object?>? metadata,
  }) {
    return Failure(
      message,
      code: 'unauthorized',
      source: source ?? 'auth',
      operation: operation,
      metadata: metadata,
    );
  }

  factory Failure.network({
    String message = 'Network error',
    Object? cause,
    StackTrace? stackTrace,
    String? source,
    String? operation,
    Map<String, Object?>? metadata,
  }) {
    return Failure(
      message,
      code: 'network_error',
      source: source ?? 'network',
      operation: operation,
      cause: cause,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  Failure copyWith({
    String? message,
    String? code,
    String? source,
    String? operation,
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    return Failure(
      message ?? this.message,
      code: code ?? this.code,
      source: source ?? this.source,
      operation: operation ?? this.operation,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      metadata: metadata ?? this.metadata,
    );
  }

  static String _normalizeExceptionMessage(Object exception) {
    final text = exception.toString().trim();
    if (text.startsWith('Exception:')) {
      return text.replaceFirst('Exception:', '').trim();
    }
    return text;
  }

  @override
  String toString() {
    return 'Failure(message: $message, code: $code, source: $source, operation: $operation)';
  }
}
