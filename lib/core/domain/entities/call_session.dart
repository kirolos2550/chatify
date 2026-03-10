import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class CallSession extends Equatable {
  const CallSession({
    required this.callId,
    required this.participantIds,
    required this.type,
    required this.state,
    required this.startedAt,
    this.endedAt,
    this.initiatorId,
    this.answeredByUserId,
  });

  final String callId;
  final List<String> participantIds;
  final CallType type;
  final CallState state;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? initiatorId;
  final String? answeredByUserId;

  @override
  List<Object?> get props => [
    callId,
    participantIds,
    type,
    state,
    startedAt,
    endedAt,
    initiatorId,
    answeredByUserId,
  ];
}
