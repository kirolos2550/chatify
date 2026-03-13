import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: CallRepository)
class CallRepositoryImpl implements CallRepository {
  CallRepositoryImpl(this._firestore, this._uuid);

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  @override
  Future<Result<void>> acceptCall({required String callId}) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'state': CallState.connecting.name,
        'answeredBy': currentUserId,
        'answeredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _failureFrom(
          e,
          stackTrace: stackTrace,
          operation: 'acceptCall',
          metadata: <String, Object?>{'callId': callId},
        ),
      );
    }
  }

  @override
  Future<Result<void>> endCall({required String callId}) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'state': CallState.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': currentUserId,
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
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || currentUserId.trim().isEmpty) {
        return const FailureResult(
          Failure('You must sign in before starting a call.'),
        );
      }
      final normalizedParticipants = participantIds
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      normalizedParticipants.add(currentUserId);
      if (normalizedParticipants.isEmpty) {
        return const FailureResult(
          Failure('No participants were provided for this call.'),
        );
      }
      if (normalizedParticipants.length != 2) {
        return const FailureResult(
          Failure('Only one-to-one calls are supported right now.'),
        );
      }
      final callId = _uuid.v4();
      final now = DateTime.now().toUtc();
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'participantIds': normalizedParticipants.toList(growable: false),
        'type': type.name,
        'state': CallState.ringing.name,
        'startedAt': now.millisecondsSinceEpoch,
        'initiatorId': currentUserId,
        'answeredBy': null,
        'answeredAt': null,
        'endedAt': null,
        'endedBy': null,
        'declinedBy': null,
        'offer': null,
        'answer': null,
      });
      return Success(
        CallSession(
          callId: callId,
          participantIds: normalizedParticipants.toList(growable: false),
          type: type,
          state: CallState.ringing,
          startedAt: now,
          initiatorId: currentUserId,
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
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return Stream<List<CallSession>>.value(<CallSession>[]);
    }
    return _firestore
        .collection(FirebasePaths.calls)
        .where('participantIds', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs.map((doc) {
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
              startedAt:
                  _toDateTime(data['startedAt']) ?? DateTime.now().toUtc(),
              endedAt: _toDateTime(data['endedAt']),
              initiatorId: data['initiatorId'] as String?,
              answeredByUserId: data['answeredBy'] as String?,
            );
          }).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
          return sessions;
        });
  }

  @override
  Future<Result<void>> rejectCall({required String callId}) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      await _firestore.collection(FirebasePaths.calls).doc(callId).set({
        'state': CallState.missed.name,
        'declinedBy': currentUserId,
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _failureFrom(
          e,
          stackTrace: stackTrace,
          operation: 'rejectCall',
          metadata: <String, Object?>{'callId': callId},
        ),
      );
    }
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
