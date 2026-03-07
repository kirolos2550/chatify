import 'package:equatable/equatable.dart';

class Receipt extends Equatable {
  const Receipt({
    required this.messageId,
    required this.userId,
    this.deliveredAt,
    this.readAt,
  });

  final String messageId;
  final String userId;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  @override
  List<Object?> get props => [messageId, userId, deliveredAt, readAt];
}
