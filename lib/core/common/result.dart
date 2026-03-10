import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;

  T? get data => switch (this) {
    Success<T>(:final value) => value,
    FailureResult<T>() => null,
  };

  Failure? get error => switch (this) {
    Success<T>() => null,
    FailureResult<T>(:final failure) => failure,
  };
}

class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);

  final Failure failure;
}

extension ResultLoggingX<T> on Result<T> {
  Result<T> onFailure(void Function(Failure failure) callback) {
    final failure = error;
    if (failure != null) {
      callback(failure);
    }
    return this;
  }

  Result<T> logIfFailure({
    required String event,
    String? source,
    String? operation,
    String? action,
    String? route,
    Map<String, Object?>? metadata,
  }) {
    final failure = error;
    if (failure == null) {
      return this;
    }

    AppLogger.error(
      failure.message,
      failure.cause ?? failure,
      failure.stackTrace,
      event: event,
      source: source ?? failure.source,
      operation: operation ?? failure.operation,
      action: action,
      route: route,
      metadata: <String, Object?>{
        if (failure.code != null) 'failureCode': failure.code,
        ...?failure.metadata,
        ...?metadata,
      },
    );
    return this;
  }
}
