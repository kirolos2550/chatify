// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:cloud_firestore/cloud_firestore.dart' as _i974;
import 'package:cloud_functions/cloud_functions.dart' as _i809;
import 'package:dio/dio.dart' as _i361;
import 'package:firebase_auth/firebase_auth.dart' as _i59;
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:firebase_storage/firebase_storage.dart' as _i457;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as _i163;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:uuid/uuid.dart' as _i706;

import '../../core/crypto/crypto_engine.dart' as _i496;
import '../../core/crypto/signal_crypto_engine.dart' as _i721;
import '../../core/data/local/app_database.dart' as _i209;
import '../../core/data/repositories/backup_repository_impl.dart' as _i45;
import '../../core/data/repositories/call_repository_impl.dart' as _i779;
import '../../core/data/repositories/contacts_repository_impl.dart' as _i205;
import '../../core/data/repositories/conversation_repository_impl.dart'
    as _i621;
import '../../core/data/repositories/device_link_repository_impl.dart' as _i924;
import '../../core/data/repositories/firebase_auth_repository.dart' as _i352;
import '../../core/data/repositories/message_repository_impl.dart' as _i25;
import '../../core/data/repositories/notification_repository_impl.dart'
    as _i968;
import '../../core/data/repositories/status_repository_impl.dart' as _i795;
import '../../core/data/services/clock.dart' as _i330;
import '../../core/data/services/device_identity_service.dart' as _i763;
import '../../core/data/services/firebase_phone_otp_gateway.dart' as _i380;
import '../../core/data/services/phone_otp_gateway.dart' as _i839;
import '../../core/domain/repositories/auth_repository.dart' as _i497;
import '../../core/domain/repositories/backup_repository.dart' as _i688;
import '../../core/domain/repositories/call_repository.dart' as _i743;
import '../../core/domain/repositories/contacts_repository.dart' as _i597;
import '../../core/domain/repositories/conversation_repository.dart' as _i714;
import '../../core/domain/repositories/device_link_repository.dart' as _i362;
import '../../core/domain/repositories/message_repository.dart' as _i441;
import '../../core/domain/repositories/notification_repository.dart' as _i399;
import '../../core/domain/repositories/status_repository.dart' as _i487;
import '../../core/notifications/chat_local_notifications.dart' as _i40;
import '../../features/auth/domain/usecases/fetch_latest_dev_otp_code_use_case.dart'
    as _i146;
import '../../features/auth/domain/usecases/request_otp_use_case.dart' as _i941;
import '../../features/auth/domain/usecases/verify_otp_use_case.dart' as _i509;
import '../../features/auth/presentation/bloc/auth_cubit.dart' as _i52;
import '../../features/backup/presentation/bloc/backup_cubit.dart' as _i690;
import '../../features/calls/domain/usecases/start_call_use_case.dart'
    as _i1018;
import '../../features/calls/presentation/bloc/calls_cubit.dart' as _i340;
import '../../features/chats/domain/usecases/send_text_message_use_case.dart'
    as _i847;
import '../../features/chats/presentation/bloc/chats_cubit.dart' as _i488;
import '../../features/contacts/domain/usecases/sync_contacts_use_case.dart'
    as _i605;
import '../../features/linked_devices/presentation/bloc/linked_devices_cubit.dart'
    as _i567;
import '../../features/search/presentation/bloc/search_cubit.dart' as _i77;
import '../../features/settings/presentation/bloc/settings_cubit.dart' as _i819;
import '../../features/status/domain/usecases/create_status_use_case.dart'
    as _i657;
import '../../features/status/presentation/bloc/status_cubit.dart' as _i484;
import 'modules/app_module.dart' as _i349;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt initGetIt({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final appModule = _$AppModule();
    gh.factory<_i77.SearchCubit>(() => _i77.SearchCubit());
    gh.factory<_i819.SettingsCubit>(() => _i819.SettingsCubit());
    gh.lazySingleton<_i361.Dio>(() => appModule.dio());
    gh.lazySingleton<_i59.FirebaseAuth>(() => appModule.firebaseAuth());
    gh.lazySingleton<_i974.FirebaseFirestore>(
      () => appModule.firebaseFirestore(),
    );
    gh.lazySingleton<_i457.FirebaseStorage>(() => appModule.firebaseStorage());
    gh.lazySingleton<_i809.FirebaseFunctions>(
      () => appModule.firebaseFunctions(),
    );
    gh.lazySingleton<_i892.FirebaseMessaging>(
      () => appModule.firebaseMessaging(),
    );
    gh.lazySingleton<_i163.FlutterLocalNotificationsPlugin>(
      () => appModule.localNotificationsPlugin(),
    );
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => appModule.secureStorage(),
    );
    gh.lazySingleton<_i706.Uuid>(() => appModule.uuid());
    gh.lazySingleton<_i209.AppDatabase>(() => appModule.appDatabase());
    gh.lazySingleton<_i330.Clock>(() => _i330.Clock());
    gh.lazySingleton<_i496.CryptoEngine>(() => _i721.SignalCryptoEngine());
    gh.lazySingleton<_i688.BackupRepository>(
      () => _i45.BackupRepositoryImpl(gh<_i558.FlutterSecureStorage>()),
    );
    gh.lazySingleton<_i714.ConversationRepository>(
      () => _i621.ConversationRepositoryImpl(
        gh<_i974.FirebaseFirestore>(),
        gh<_i59.FirebaseAuth>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i362.DeviceLinkRepository>(
      () => _i924.DeviceLinkRepositoryImpl(
        gh<_i974.FirebaseFirestore>(),
        gh<_i59.FirebaseAuth>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i839.PhoneOtpGateway>(
      () => _i380.FirebasePhoneOtpGateway(
        gh<_i59.FirebaseAuth>(),
        gh<_i361.Dio>(),
      ),
    );
    gh.lazySingleton<_i763.DeviceIdentityService>(
      () => _i763.DeviceIdentityService(
        gh<_i558.FlutterSecureStorage>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i40.ChatLocalNotifications>(
      () => _i40.ChatLocalNotifications(
        gh<_i163.FlutterLocalNotificationsPlugin>(),
      ),
    );
    gh.lazySingleton<_i441.MessageRepository>(
      () => _i25.MessageRepositoryImpl(
        gh<_i974.FirebaseFirestore>(),
        gh<_i209.AppDatabase>(),
      ),
    );
    gh.factory<_i847.SendTextMessageUseCase>(
      () => _i847.SendTextMessageUseCase(
        gh<_i441.MessageRepository>(),
        gh<_i496.CryptoEngine>(),
        gh<_i763.DeviceIdentityService>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.factory<_i567.LinkedDevicesCubit>(
      () => _i567.LinkedDevicesCubit(gh<_i362.DeviceLinkRepository>()),
    );
    gh.lazySingleton<_i743.CallRepository>(
      () => _i779.CallRepositoryImpl(
        gh<_i974.FirebaseFirestore>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i497.AuthRepository>(
      () => _i352.FirebaseAuthRepository(
        gh<_i59.FirebaseAuth>(),
        gh<_i974.FirebaseFirestore>(),
        gh<_i558.FlutterSecureStorage>(),
        gh<_i839.PhoneOtpGateway>(),
      ),
    );
    gh.factory<_i488.ChatsCubit>(
      () => _i488.ChatsCubit(gh<_i714.ConversationRepository>()),
    );
    gh.lazySingleton<_i487.StatusRepository>(
      () => _i795.StatusRepositoryImpl(gh<_i974.FirebaseFirestore>()),
    );
    gh.factory<_i146.FetchLatestDevOtpCodeUseCase>(
      () => _i146.FetchLatestDevOtpCodeUseCase(gh<_i497.AuthRepository>()),
    );
    gh.factory<_i941.RequestOtpUseCase>(
      () => _i941.RequestOtpUseCase(gh<_i497.AuthRepository>()),
    );
    gh.factory<_i509.VerifyOtpUseCase>(
      () => _i509.VerifyOtpUseCase(gh<_i497.AuthRepository>()),
    );
    gh.lazySingleton<_i597.ContactsRepository>(
      () => _i205.ContactsRepositoryImpl(gh<_i974.FirebaseFirestore>()),
    );
    gh.factory<_i690.BackupCubit>(
      () => _i690.BackupCubit(gh<_i688.BackupRepository>()),
    );
    gh.lazySingleton<_i399.NotificationRepository>(
      () => _i968.NotificationRepositoryImpl(
        gh<_i892.FirebaseMessaging>(),
        gh<_i40.ChatLocalNotifications>(),
      ),
    );
    gh.factory<_i1018.StartCallUseCase>(
      () => _i1018.StartCallUseCase(gh<_i743.CallRepository>()),
    );
    gh.factory<_i340.CallsCubit>(
      () => _i340.CallsCubit(gh<_i743.CallRepository>()),
    );
    gh.factory<_i605.SyncContactsUseCase>(
      () => _i605.SyncContactsUseCase(gh<_i597.ContactsRepository>()),
    );
    gh.factory<_i484.StatusCubit>(
      () => _i484.StatusCubit(gh<_i487.StatusRepository>()),
    );
    gh.factory<_i657.CreateStatusUseCase>(
      () => _i657.CreateStatusUseCase(
        gh<_i487.StatusRepository>(),
        gh<_i706.Uuid>(),
      ),
    );
    gh.factory<_i52.AuthCubit>(
      () => _i52.AuthCubit(
        gh<_i941.RequestOtpUseCase>(),
        gh<_i509.VerifyOtpUseCase>(),
        gh<_i146.FetchLatestDevOtpCodeUseCase>(),
      ),
    );
    return this;
  }
}

class _$AppModule extends _i349.AppModule {}
