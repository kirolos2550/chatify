import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class OutboxOp extends Equatable {
  const OutboxOp({
    required this.id,
    required this.type,
    required this.payloadJson,
    required this.createdAt,
    required this.retryCount,
    this.nextRetryAt,
  });

  final String id;
  final OutboxOpType type;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextRetryAt;

  @override
  List<Object?> get props => [
    id,
    type,
    payloadJson,
    createdAt,
    retryCount,
    nextRetryAt,
  ];
}
