import 'dart:developer' as developer;

abstract final class AppLogger {
  static void info(String message) {
    developer.log(message, name: 'chatify.info');
  }

  static void error(String message, Object error, StackTrace? stackTrace) {
    developer.log(
      message,
      name: 'chatify.error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
