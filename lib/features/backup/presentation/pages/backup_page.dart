import 'package:chatify/app/di/injection.dart';
import 'package:chatify/features/backup/presentation/bloc/backup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool _enabled = true;

  bool get _hasWiredBackup => getIt.isRegistered<BackupCubit>();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredBackup) {
      return _BackupScaffold(
        enabled: _enabled,
        passwordController: _passwordController,
        loading: false,
        message: 'Backup is running in local demo mode.',
        onEnabledChanged: (value) => setState(() => _enabled = value),
        onEnableBackup: _localEnable,
        onRestoreBackup: _localRestore,
      );
    }

    return BlocProvider(
      create: (_) => getIt<BackupCubit>(),
      child: BlocConsumer<BackupCubit, BackupState>(
        listener: (context, state) {
          final message = state.message;
          if (message != null && message.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          final loading = state.status == BackupStatus.loading;
          return _BackupScaffold(
            enabled: _enabled,
            passwordController: _passwordController,
            loading: loading,
            message: state.message,
            onEnabledChanged: (value) => setState(() => _enabled = value),
            onEnableBackup: () async {
              final password = _passwordController.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password is required')),
                );
                return;
              }
              await context.read<BackupCubit>().enable(password);
            },
            onRestoreBackup: () async {
              final password = _passwordController.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password is required')),
                );
                return;
              }
              await context.read<BackupCubit>().restore(password);
            },
          );
        },
      ),
    );
  }

  Future<void> _localEnable() async {
    if (_passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password is required')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Backup enabled locally')));
  }

  Future<void> _localRestore() async {
    if (_passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password is required')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Backup restored locally')));
  }
}

class _BackupScaffold extends StatelessWidget {
  const _BackupScaffold({
    required this.enabled,
    required this.passwordController,
    required this.loading,
    required this.message,
    required this.onEnabledChanged,
    required this.onEnableBackup,
    required this.onRestoreBackup,
  });

  final bool enabled;
  final TextEditingController passwordController;
  final bool loading;
  final String? message;
  final ValueChanged<bool> onEnabledChanged;
  final Future<void> Function() onEnableBackup;
  final Future<void> Function() onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encrypted backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: enabled,
            title: const Text('Enable E2E backup'),
            subtitle: const Text('Backup key remains only on your devices'),
            onChanged: loading ? null : onEnabledChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passwordController,
            obscureText: true,
            enabled: !loading,
            decoration: const InputDecoration(labelText: 'Backup password'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: loading || !enabled ? null : onEnableBackup,
                  child: Text(loading ? 'Working...' : 'Enable backup'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading ? null : onRestoreBackup,
                  child: const Text('Restore'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Last backup'),
            subtitle: Text(enabled ? 'Configured' : 'Disabled'),
          ),
          if (message != null && message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
