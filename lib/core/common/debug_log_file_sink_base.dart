import 'dart:async';

typedef LogDirectoryPathProvider = Future<String> Function();
typedef Clock = DateTime Function();

abstract class DebugLogFileSink {
  Future<void> init({required String sessionId});
  Future<void> writeLine(String line);
  Future<void> flush();
  Future<void> close();
  Future<List<String>> listSessionLogPaths({int limit = 10});
  String? get currentFilePath;
}
