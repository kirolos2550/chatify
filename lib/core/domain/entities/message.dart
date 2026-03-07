import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class Message extends Equatable {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.ciphertext,
    required this.clientTimestamp,
    required this.localStatus,
    required this.deviceId,
    this.serverSeq,
    this.editedAt,
    this.deletedForAllAt,
    this.deletedForUserIds = const [],
    this.deliveredToUserIds = const [],
    this.readByUserIds = const [],
    this.starredByUserIds = const [],
    this.pinnedByUserIds = const [],
    this.reactionsByUser = const {},
    this.replyToMessageId,
    this.e2eeVersion = 'signal-v1',
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String ciphertext;
  final DateTime clientTimestamp;
  final int? serverSeq;
  final DateTime? editedAt;
  final DateTime? deletedForAllAt;
  final List<String> deletedForUserIds;
  final List<String> deliveredToUserIds;
  final List<String> readByUserIds;
  final List<String> starredByUserIds;
  final List<String> pinnedByUserIds;
  final Map<String, String> reactionsByUser;
  final LocalMessageStatus localStatus;
  final String deviceId;
  final String? replyToMessageId;
  final String e2eeVersion;

  @override
  List<Object?> get props => [
    id,
    conversationId,
    senderId,
    type,
    ciphertext,
    clientTimestamp,
    serverSeq,
    editedAt,
    deletedForAllAt,
    deletedForUserIds,
    deliveredToUserIds,
    readByUserIds,
    starredByUserIds,
    pinnedByUserIds,
    reactionsByUser,
    localStatus,
    deviceId,
    replyToMessageId,
    e2eeVersion,
  ];
}
