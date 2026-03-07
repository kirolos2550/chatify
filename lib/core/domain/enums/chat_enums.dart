enum ConversationType { direct, group }

enum ConversationRole { owner, admin, member }

enum MessageType { text, image, video, file, voice, videoNote, system }

enum LocalMessageStatus { queued, sending, sent, delivered, read, failed }

enum CallType { voice, video }

enum CallState { ringing, connecting, connected, ended, missed, failed }

enum OutboxOpType {
  sendMessage,
  editMessage,
  deleteMessage,
  react,
  receipt,
  typing,
  presence,
}
