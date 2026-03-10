import 'package:chatify/app/di/injection.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/log_share_service.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/data/services/user_privacy_service.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _readReceiptsEnabled = true;
  bool _lastSeenVisible = true;
  bool _typingVisibilityEnabled = true;
  bool _privacyUpdating = false;
  bool _sharingLogs = false;

  bool get _hasAuthRepository =>
      getIt.isRegistered<AuthRepository>() && Firebase.apps.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

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

    return _SettingsScaffold(
      profileName: resolvedProfileName,
      profileSubtitle: resolvedProfileSubtitle,
      profileAvatarUrl: user?.photoURL,
      readReceipts: _readReceiptsEnabled,
      lastSeenVisible: _lastSeenVisible,
      typingVisibilityEnabled: _typingVisibilityEnabled,
      privacyUpdating: _privacyUpdating,
      onReadReceiptsChanged: (value) =>
          _updatePrivacy(readReceiptsEnabled: value),
      onLastSeenChanged: (value) => _updatePrivacy(lastSeenVisible: value),
      onTypingVisibilityChanged: (value) =>
          _updatePrivacy(typingVisibilityEnabled: value),
      currentLanguageCode: AppLocaleController.instance.localeCode,
      onChangeLanguage: _changeLanguage,
      onOpenProfile: _openMyProfile,
      sharingLogs: _sharingLogs,
      onExportLogs: _exportDebugLogs,
      onSignOut: _signOut,
    );
  }

  Future<void> _loadPrivacySettings() async {
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    AppLogger.breadcrumb(
      'settings.privacy.load.start',
      action: 'settings.privacy.load',
    );
    setState(() => _privacyUpdating = true);
    try {
      final settings = await UserPrivacyService.loadMySettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _readReceiptsEnabled = settings.readReceiptsEnabled;
        _lastSeenVisible = settings.lastSeenVisible;
        _typingVisibilityEnabled = settings.typingVisibilityEnabled;
      });
      AppLogger.info(
        'Privacy settings loaded',
        event: 'settings.privacy.load.success',
        action: 'settings.privacy.load',
      );
    } catch (error) {
      AppLogger.error(
        'Failed to load privacy settings',
        error,
        StackTrace.current,
        event: 'settings.privacy.load.failure',
        action: 'settings.privacy.load',
        source: 'SettingsPage',
        operation: 'loadPrivacySettings',
      );
      if (!mounted) {
        return;
      }
      _showSnack('Failed to load privacy settings: $error');
    } finally {
      if (mounted) {
        setState(() => _privacyUpdating = false);
      }
    }
  }

  Future<void> _updatePrivacy({
    bool? readReceiptsEnabled,
    bool? lastSeenVisible,
    bool? typingVisibilityEnabled,
  }) async {
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      _showSnack('Sign in first to change privacy settings');
      return;
    }
    AppLogger.breadcrumb(
      'settings.privacy.update.start',
      action: 'settings.privacy.update',
      metadata: <String, Object?>{
        'readReceiptsEnabled': readReceiptsEnabled,
        'lastSeenVisible': lastSeenVisible,
        'typingVisibilityEnabled': typingVisibilityEnabled,
      },
    );
    setState(() {
      if (readReceiptsEnabled != null) {
        _readReceiptsEnabled = readReceiptsEnabled;
      }
      if (lastSeenVisible != null) {
        _lastSeenVisible = lastSeenVisible;
      }
      if (typingVisibilityEnabled != null) {
        _typingVisibilityEnabled = typingVisibilityEnabled;
      }
      _privacyUpdating = true;
    });

    try {
      await UserPrivacyService.updateMySettings(
        readReceiptsEnabled: readReceiptsEnabled,
        lastSeenVisible: lastSeenVisible,
        typingVisibilityEnabled: typingVisibilityEnabled,
      );
      AppLogger.info(
        'Privacy settings updated',
        event: 'settings.privacy.update.success',
        action: 'settings.privacy.update',
        metadata: <String, Object?>{
          'readReceiptsEnabled': readReceiptsEnabled,
          'lastSeenVisible': lastSeenVisible,
          'typingVisibilityEnabled': typingVisibilityEnabled,
        },
      );
    } catch (error) {
      AppLogger.error(
        'Failed to update privacy settings',
        error,
        StackTrace.current,
        event: 'settings.privacy.update.failure',
        action: 'settings.privacy.update',
        source: 'SettingsPage',
        operation: 'updatePrivacy',
        metadata: <String, Object?>{
          'readReceiptsEnabled': readReceiptsEnabled,
          'lastSeenVisible': lastSeenVisible,
          'typingVisibilityEnabled': typingVisibilityEnabled,
        },
      );
      if (!mounted) {
        return;
      }
      _showSnack('Failed to update privacy settings: $error');
      await _loadPrivacySettings();
      return;
    }

    if (mounted) {
      setState(() => _privacyUpdating = false);
    }
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
    await context.push('/profile/${Uri.encodeComponent(uid)}');
    if (mounted) {
      setState(() {});
    }
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
    AppLogger.breadcrumb(
      'settings.sign_out.start',
      action: 'settings.sign_out',
    );
    if (_hasAuthRepository) {
      final result = await getIt<AuthRepository>().signOut();
      result.logIfFailure(
        event: 'settings.sign_out.failure',
        action: 'settings.sign_out',
        source: 'SettingsPage',
        operation: 'signOut',
      );
      if (result.error == null) {
        AppLogger.info(
          'Sign out succeeded',
          event: 'settings.sign_out.success',
          action: 'settings.sign_out',
        );
      }
    }
    if (!mounted) {
      return;
    }
    context.go('/auth');
  }

  Future<void> _exportDebugLogs() async {
    if (_sharingLogs) {
      return;
    }
    setState(() => _sharingLogs = true);
    final result = await shareLatestDebugLogs(action: 'settings.logs.share');
    if (mounted) {
      _showSnack(result.message);
      setState(() => _sharingLogs = false);
    }
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
    required this.typingVisibilityEnabled,
    required this.privacyUpdating,
    required this.onReadReceiptsChanged,
    required this.onLastSeenChanged,
    required this.onTypingVisibilityChanged,
    required this.currentLanguageCode,
    required this.onChangeLanguage,
    required this.onOpenProfile,
    required this.sharingLogs,
    required this.onExportLogs,
    required this.onSignOut,
  });

  final String profileName;
  final String profileSubtitle;
  final String? profileAvatarUrl;
  final bool readReceipts;
  final bool lastSeenVisible;
  final bool typingVisibilityEnabled;
  final bool privacyUpdating;
  final ValueChanged<bool> onReadReceiptsChanged;
  final ValueChanged<bool> onLastSeenChanged;
  final ValueChanged<bool> onTypingVisibilityChanged;
  final String currentLanguageCode;
  final Future<void> Function() onChangeLanguage;
  final Future<void> Function() onOpenProfile;
  final bool sharingLogs;
  final Future<void> Function() onExportLogs;
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
          if (privacyUpdating) const LinearProgressIndicator(minHeight: 2),
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
            onChanged: privacyUpdating ? null : onReadReceiptsChanged,
          ),
          SwitchListTile(
            value: lastSeenVisible,
            title: Text(l10n.lastSeenVisibility),
            onChanged: privacyUpdating ? null : onLastSeenChanged,
          ),
          SwitchListTile(
            value: typingVisibilityEnabled,
            title: const Text('Typing visibility'),
            onChanged: privacyUpdating ? null : onTypingVisibilityChanged,
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
            leading: sharingLogs
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bug_report_outlined),
            title: const Text('Export debug logs'),
            subtitle: const Text('Share latest session logs for diagnostics'),
            onTap: sharingLogs ? null : onExportLogs,
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
