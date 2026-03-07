import 'package:equatable/equatable.dart';

class Reaction extends Equatable {
  const Reaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  @override
  List<Object?> get props => [messageId, userId, emoji, createdAt];
}
