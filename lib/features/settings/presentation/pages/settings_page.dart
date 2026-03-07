import 'package:chatify/app/di/injection.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:chatify/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _localReadReceipts = true;
  bool _localLastSeen = true;

  bool get _hasWiredSettings => getIt.isRegistered<SettingsCubit>();
  bool get _hasAuthRepository =>
      getIt.isRegistered<AuthRepository>() && Firebase.apps.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;
    final resolvedProfileName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : l10n.profileName;
    final resolvedProfileSubtitle =
        (user?.phoneNumber?.trim().isNotEmpty ?? false)
        ? user!.phoneNumber!.trim()
        : l10n.profileSubtitle;

    if (!_hasWiredSettings) {
      return _SettingsScaffold(
        profileName: resolvedProfileName,
        profileSubtitle: resolvedProfileSubtitle,
        profileAvatarUrl: user?.photoURL,
        readReceipts: _localReadReceipts,
        lastSeenVisible: _localLastSeen,
        onReadReceiptsChanged: (value) =>
            setState(() => _localReadReceipts = value),
        onLastSeenChanged: (value) => setState(() => _localLastSeen = value),
        currentLanguageCode: AppLocaleController.instance.localeCode,
        onChangeLanguage: _changeLanguage,
        onOpenProfile: _openMyProfile,
        onSignOut: _signOut,
      );
    }

    return BlocProvider(
      create: (_) => getIt<SettingsCubit>(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return _SettingsScaffold(
            profileName: resolvedProfileName,
            profileSubtitle: resolvedProfileSubtitle,
            profileAvatarUrl: user?.photoURL,
            readReceipts: state.readReceiptsEnabled,
            lastSeenVisible: state.lastSeenVisible,
            onReadReceiptsChanged: (value) =>
                context.read<SettingsCubit>().toggleReadReceipts(value),
            onLastSeenChanged: (value) =>
                setState(() => _localLastSeen = value),
            currentLanguageCode: AppLocaleController.instance.localeCode,
            onChangeLanguage: _changeLanguage,
            onOpenProfile: _openMyProfile,
            onSignOut: _signOut,
          );
        },
      ),
    );
  }

  Future<void> _openMyProfile() async {
    if (Firebase.apps.isEmpty) {
      _showSnack('Profile is unavailable in demo mode');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _showSnack('Sign in first to manage your profile');
      return;
    }
    if (!mounted) {
      return;
    }
    context.push('/profile/${Uri.encodeComponent(uid)}');
  }

  Future<void> _changeLanguage() async {
    final selectedCode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final current = AppLocaleController.instance.localeCode;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.languageSystem),
                trailing: current == 'system' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop('system'),
              ),
              ListTile(
                title: Text(l10n.languageArabic),
                trailing: current == 'ar' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop('ar'),
              ),
              ListTile(
                title: Text(l10n.languageEnglish),
                trailing: current == 'en' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop('en'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedCode == null) {
      return;
    }

    if (selectedCode == 'system') {
      await AppLocaleController.instance.setSystemLocale();
    } else {
      await AppLocaleController.instance.setLocaleCode(selectedCode);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _signOut() async {
    if (_hasAuthRepository) {
      await getIt<AuthRepository>().signOut();
    }
    if (!mounted) {
      return;
    }
    context.go('/auth');
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.profileName,
    required this.profileSubtitle,
    this.profileAvatarUrl,
    required this.readReceipts,
    required this.lastSeenVisible,
    required this.onReadReceiptsChanged,
    required this.onLastSeenChanged,
    required this.currentLanguageCode,
    required this.onChangeLanguage,
    required this.onOpenProfile,
    required this.onSignOut,
  });

  final String profileName;
  final String profileSubtitle;
  final String? profileAvatarUrl;
  final bool readReceipts;
  final bool lastSeenVisible;
  final ValueChanged<bool> onReadReceiptsChanged;
  final ValueChanged<bool> onLastSeenChanged;
  final String currentLanguageCode;
  final Future<void> Function() onChangeLanguage;
  final Future<void> Function() onOpenProfile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageLabel = switch (currentLanguageCode) {
      'ar' => l10n.languageArabic,
      'en' => l10n.languageEnglish,
      _ => l10n.languageSystem,
    };
    final avatarImage = _avatarImage(profileAvatarUrl);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarImage,
              child: avatarImage == null ? const Icon(Icons.person) : null,
            ),
            title: Text(profileName),
            subtitle: Text(profileSubtitle),
            trailing: const Icon(Icons.edit_outlined),
            onTap: onOpenProfile,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l10n.language),
            subtitle: Text(languageLabel),
            onTap: onChangeLanguage,
          ),
          SwitchListTile(
            value: readReceipts,
            title: Text(l10n.readReceipts),
            onChanged: onReadReceiptsChanged,
          ),
          SwitchListTile(
            value: lastSeenVisible,
            title: Text(l10n.lastSeenVisibility),
            onChanged: onLastSeenChanged,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(l10n.linkedDevices),
            onTap: () => context.push('/linked-devices'),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.encryptedBackup),
            onTap: () => context.push('/backup'),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('WhatsApp Business (Beta)'),
            subtitle: const Text('Templates, webhook and cloud API bridge'),
            onTap: () => context.push('/business/whatsapp'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.signOut),
            onTap: () => onSignOut(),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatarImage(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') || !uri.hasAuthority) {
      return null;
    }
    return NetworkImage(raw);
  }
}
