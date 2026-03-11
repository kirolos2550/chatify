import 'package:equatable/equatable.dart';

class ContactCandidate extends Equatable {
  const ContactCandidate({
    required this.displayName,
    required this.rawPhone,
    required this.normalizedPhoneE164,
    required this.phoneDigits,
    required this.isRegistered,
    this.registeredUserId,
  });

  final String displayName;
  final String rawPhone;
  final String normalizedPhoneE164;
  final String phoneDigits;
  final String? registeredUserId;
  final bool isRegistered;

  @override
  List<Object?> get props => [
    displayName,
    rawPhone,
    normalizedPhoneE164,
    phoneDigits,
    registeredUserId,
    isRegistered,
  ];
}
