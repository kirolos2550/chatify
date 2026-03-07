import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';

abstract interface class CallRepository {
  Stream<List<CallSession>> watchCalls();

  Future<Result<CallSession>> startCall({
    required List<String> participantIds,
    required CallType type,
  });

  Future<Result<void>> endCall({required String callId});
}
