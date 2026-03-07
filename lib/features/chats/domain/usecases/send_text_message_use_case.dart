import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/crypto/crypto_engine.dart';
import 'package:chatify/core/data/services/device_identity_service.dart';
import 'package:chatify/core/domain/entities/message.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

class SendTextMessageParams {
  const SendTextMessageParams({
    required this.conversationId,
    required this.senderId,
    required this.plaintext,
    required this.peerDeviceId,
    this.messageType = MessageType.text,
    this.replyToMessageId,
  });

  final String conversationId;
  final String senderId;
  final String plaintext;
  final String peerDeviceId;
  final MessageType messageType;
  final String? replyToMessageId;
}

@injectable
class SendTextMessageUseCase
    implements UseCase<Result<void>, SendTextMessageParams> {
  SendTextMessageUseCase(
    this._messageRepository,
    this._cryptoEngine,
    this._deviceIdentity,
    this._uuid,
  );

  final MessageRepository _messageRepository;
  final CryptoEngine _cryptoEngine;
  final DeviceIdentityService _deviceIdentity;
  final Uuid _uuid;

  @override
  Future<Result<void>> call(SendTextMessageParams params) async {
    final ciphertext = await _cryptoEngine.encrypt(
      plaintext: params.plaintext,
      peerDeviceId: params.peerDeviceId,
    );
    final deviceId = await _deviceIdentity.getOrCreateDeviceId();
    final message = Message(
      id: _uuid.v4(),
      conversationId: params.conversationId,
      senderId: params.senderId,
      type: params.messageType,
      ciphertext: ciphertext,
      clientTimestamp: DateTime.now().toUtc(),
      localStatus: LocalMessageStatus.sending,
      deviceId: deviceId,
      replyToMessageId: params.replyToMessageId,
      e2eeVersion: 'signal-v1',
    );
    return _messageRepository.sendMessage(
      conversationId: params.conversationId,
      message: message,
    );
  }
}
