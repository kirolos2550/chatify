import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.phone,
    required this.displayName,
    required this.createdAt,
    this.avatarUrl,
    this.about,
  });

  final String id;
  final String phone;
  final String displayName;
  final String? avatarUrl;
  final String? about;
  final DateTime createdAt;

  @override
  List<Object?> get props => [
    id,
    phone,
    displayName,
    avatarUrl,
    about,
    createdAt,
  ];
}
