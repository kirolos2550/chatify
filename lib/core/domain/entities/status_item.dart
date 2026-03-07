import 'package:equatable/equatable.dart';

class StatusItem extends Equatable {
  const StatusItem({
    required this.id,
    required this.authorId,
    required this.mediaType,
    required this.ciphertextRef,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String authorId;
  final String mediaType;
  final String ciphertextRef;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  List<Object?> get props => [
    id,
    authorId,
    mediaType,
    ciphertextRef,
    createdAt,
    expiresAt,
  ];
}
