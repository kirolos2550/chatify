import 'package:equatable/equatable.dart';

class Device extends Equatable {
  const Device({
    required this.deviceId,
    required this.userId,
    required this.publicIdentityKey,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String userId;
  final String publicIdentityKey;
  final DateTime lastSeenAt;

  @override
  List<Object?> get props => [deviceId, userId, publicIdentityKey, lastSeenAt];
}
