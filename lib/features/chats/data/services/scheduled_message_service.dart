import 'dart:async';
import 'dart:convert';

import 'package:chatify/core/common/app_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

typedef ScheduledMessageDispatcher =
    Future<bool> Function(ScheduledMessageTask task);

class ScheduledMessageTask {
  const ScheduledMessageTask({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.plaintext,
    required this.scheduledFor,
    required this.createdAt,
    this.replyToMessageId,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String plaintext;
  final DateTime scheduledFor;
  final DateTime createdAt;
  final String? replyToMessageId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'plaintext': plaintext,
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'replyToMessageId': replyToMessageId,
    };
  }

  static ScheduledMessageTask? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final conversationId = json['conversationId']?.toString().trim() ?? '';
    final senderId = json['senderId']?.toString().trim() ?? '';
    final plaintext = json['plaintext']?.toString() ?? '';
    final scheduledForRaw = json['scheduledFor']?.toString();
    final createdAtRaw = json['createdAt']?.toString();

    final scheduledFor = scheduledForRaw == null
        ? null
        : DateTime.tryParse(scheduledForRaw)?.toUtc();
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw)?.toUtc();

    if (id.isEmpty ||
        conversationId.isEmpty ||
        senderId.isEmpty ||
        plaintext.trim().isEmpty ||
        scheduledFor == null ||
        createdAt == null) {
      return null;
    }

    final replyToMessageId = json['replyToMessageId']?.toString().trim();
    return ScheduledMessageTask(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      plaintext: plaintext,
      scheduledFor: scheduledFor,
      createdAt: createdAt,
      replyToMessageId: replyToMessageId == null || replyToMessageId.isEmpty
          ? null
          : replyToMessageId,
    );
  }
}

class ScheduledMessageService {
  ScheduledMessageService._();

  static final ScheduledMessageService instance = ScheduledMessageService._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _storageKey = 'scheduled_messages_v1';
  static const Uuid _uuid = Uuid();

  final List<ScheduledMessageTask> _tasks = <ScheduledMessageTask>[];
  final Map<String, Timer> _timersById = <String, Timer>{};

  ScheduledMessageDispatcher? _dispatcher;
  String? Function()? _currentUserIdProvider;
  Future<void>? _loadFuture;
  bool _processing = false;

  Future<void> initialize({
    required ScheduledMessageDispatcher dispatcher,
    required String? Function() currentUserIdProvider,
  }) async {
    _dispatcher = dispatcher;
    _currentUserIdProvider = currentUserIdProvider;
    await _ensureLoaded();
    _armTimers();
    await processDueMessages();
  }

  Future<ScheduledMessageTask> scheduleTextMessage({
    required String conversationId,
    required String senderId,
    required String plaintext,
    required DateTime scheduledFor,
    String? replyToMessageId,
  }) async {
    await _ensureLoaded();

    final task = ScheduledMessageTask(
      id: _uuid.v4(),
      conversationId: conversationId.trim(),
      senderId: senderId.trim(),
      plaintext: plaintext.trim(),
      scheduledFor: scheduledFor.toUtc(),
      createdAt: DateTime.now().toUtc(),
      replyToMessageId: replyToMessageId?.trim().isEmpty ?? true
          ? null
          : replyToMessageId!.trim(),
    );

    _tasks.add(task);
    _sortTasks();
    await _persist();
    _armTimer(task);

    AppLogger.info(
      'Scheduled message saved',
      event: 'chat.schedule.created',
      action: 'chat.schedule',
      metadata: <String, Object?>{
        'conversationId': task.conversationId,
        'scheduledFor': task.scheduledFor.toIso8601String(),
      },
    );

    return task;
  }

  Future<void> processDueMessages() async {
    await _ensureLoaded();
    if (_processing) {
      return;
    }
    _processing = true;

    try {
      final currentUserId = _normalizedCurrentUserId();
      if (currentUserId == null) {
        return;
      }

      final now = DateTime.now().toUtc();
      final dueTasks =
          _tasks
              .where(
                (task) =>
                    task.senderId == currentUserId &&
                    !task.scheduledFor.isAfter(now),
              )
              .toList(growable: false)
            ..sort(
              (left, right) => left.scheduledFor.compareTo(right.scheduledFor),
            );

      for (final task in dueTasks) {
        await _dispatchTask(task);
      }
    } finally {
      _processing = false;
      _armTimers();
    }
  }

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      _tasks
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map((entry) {
            final normalized = entry.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            return ScheduledMessageTask.fromJson(normalized);
          }).whereType<ScheduledMessageTask>(),
        );
      _sortTasks();
    } catch (_) {
      _tasks.clear();
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode(
      _tasks.map((task) => task.toJson()).toList(growable: false),
    );
    await _storage.write(key: _storageKey, value: payload);
  }

  void _armTimers() {
    for (final timer in _timersById.values) {
      timer.cancel();
    }
    _timersById.clear();

    final currentUserId = _normalizedCurrentUserId();
    if (currentUserId == null) {
      return;
    }

    for (final task in _tasks) {
      if (task.senderId != currentUserId) {
        continue;
      }
      _armTimer(task);
    }
  }

  void _armTimer(ScheduledMessageTask task) {
    final currentUserId = _normalizedCurrentUserId();
    if (currentUserId == null || task.senderId != currentUserId) {
      return;
    }

    final delay = task.scheduledFor.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      return;
    }

    _timersById[task.id]?.cancel();
    _timersById[task.id] = Timer(delay, () {
      unawaited(_dispatchTaskById(task.id));
    });
  }

  Future<void> _dispatchTaskById(String taskId) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return;
    }
    await _dispatchTask(task);
    _armTimers();
  }

  Future<void> _dispatchTask(ScheduledMessageTask task) async {
    _timersById.remove(task.id)?.cancel();

    final currentUserId = _normalizedCurrentUserId();
    final dispatcher = _dispatcher;
    if (dispatcher == null ||
        currentUserId == null ||
        currentUserId != task.senderId) {
      return;
    }

    final sent = await dispatcher(task);
    if (!sent) {
      AppLogger.warning(
        'Scheduled message dispatch deferred',
        event: 'chat.schedule.dispatch_deferred',
        action: 'chat.schedule',
        metadata: <String, Object?>{
          'conversationId': task.conversationId,
          'scheduledFor': task.scheduledFor.toIso8601String(),
        },
      );
      return;
    }

    _tasks.removeWhere((candidate) => candidate.id == task.id);
    await _persist();
    AppLogger.info(
      'Scheduled message dispatched',
      event: 'chat.schedule.dispatched',
      action: 'chat.schedule',
      metadata: <String, Object?>{
        'conversationId': task.conversationId,
        'scheduledFor': task.scheduledFor.toIso8601String(),
      },
    );
  }

  ScheduledMessageTask? _findTaskById(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  String? _normalizedCurrentUserId() {
    final value = _currentUserIdProvider?.call()?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  void _sortTasks() {
    _tasks.sort(
      (left, right) => left.scheduledFor.compareTo(right.scheduledFor),
    );
  }
}
