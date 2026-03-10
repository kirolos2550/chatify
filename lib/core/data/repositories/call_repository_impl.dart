import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: CallRepository)
class CallRepositoryImpl implements CallRepository {
  CallRepositoryImpl(this._firestore, this._uuid);

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  @override
  Future<Result<void>> endCall({required String callId}) async {
    try {
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'state': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _failureFrom(
          e,
          stackTrace: stackTrace,
          operation: 'endCall',
          metadata: <String, Object?>{'callId': callId},
        ),
      );
    }
  }

  @override
  Future<Result<CallSession>> startCall({
    required List<String> participantIds,
    required CallType type,
  }) async {
    try {
      final callId = _uuid.v4();
      final now = DateTime.now().toUtc();
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'participantIds': participantIds,
        'type': type.name,
        'state': CallState.ringing.name,
        'startedAt': now.millisecondsSinceEpoch,
      });
      return Success(
        CallSession(
          callId: callId,
          participantIds: participantIds,
          type: type,
          state: CallState.ringing,
          startedAt: now,
        ),
      );
    } catch (e, stackTrace) {
      return FailureResult(
        _failureFrom(
          e,
          stackTrace: stackTrace,
          operation: 'startCall',
          metadata: <String, Object?>{
            'participantCount': participantIds.length,
            'type': type.name,
          },
        ),
      );
    }
  }

  @override
  Stream<List<CallSession>> watchCalls() {
    return _firestore.collection(FirebasePaths.calls).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return CallSession(
          callId: doc.id,
          participantIds: List<String>.from(
            data['participantIds'] as List? ?? const [],
          ),
          type: (data['type'] as String?) == CallType.video.name
              ? CallType.video
              : CallType.voice,
          state: CallState.values.firstWhere(
            (e) => e.name == (data['state'] as String?),
            orElse: () => CallState.ringing,
          ),
          startedAt: _toDateTime(data['startedAt']) ?? DateTime.now().toUtc(),
          endedAt: _toDateTime(data['endedAt']),
        );
      }).toList();
    });
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  Failure _failureFrom(
    Object error, {
    required String operation,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    final failure = Failure.fromException(
      error,
      stackTrace: stackTrace,
      source: 'CallRepositoryImpl',
      operation: operation,
      metadata: metadata,
    );
    AppLogger.error(
      failure.message,
      failure.cause ?? error,
      failure.stackTrace ?? stackTrace,
      event: 'calls.repository.failure',
      source: failure.source,
      operation: failure.operation,
      action: 'calls.repository',
      metadata: failure.metadata,
    );
    return failure;
  }
}
