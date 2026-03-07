import 'package:chatify/app/di/injection.dart';
import 'package:chatify/features/linked_devices/presentation/bloc/linked_devices_cubit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LinkedDevicesPage extends StatefulWidget {
  const LinkedDevicesPage({super.key});

  @override
  State<LinkedDevicesPage> createState() => _LinkedDevicesPageState();
}

class _LinkedDevicesPageState extends State<LinkedDevicesPage> {
  final List<_LocalDeviceEntry> _localEntries = [
    _LocalDeviceEntry(
      deviceName: 'Macbook Pro',
      lastActive: DateTime.now().subtract(const Duration(minutes: 3)),
    ),
  ];

  bool get _hasWiredDevices =>
      getIt.isRegistered<LinkedDevicesCubit>() && Firebase.apps.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredDevices) {
      return _DevicesScaffold(
        entries: _localEntries,
        loading: false,
        busy: false,
        showDemoHint: true,
        onStartLink: _startLocalLink,
        onConfirmLink: _confirmLocalLink,
      );
    }

    return BlocProvider(
      create: (_) => getIt<LinkedDevicesCubit>(),
      child: BlocConsumer<LinkedDevicesCubit, LinkedDevicesState>(
        listener: (context, state) async {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
          final code = state.pendingLinkCode;
          if (code != null && code.isNotEmpty) {
            await _showLinkCode(code);
          }
        },
        builder: (context, state) {
          final entries = state.items
              .map(
                (item) => _LocalDeviceEntry(
                  deviceName: item.deviceId,
                  lastActive: item.lastSeenAt,
                ),
              )
              .toList();
          return _DevicesScaffold(
            entries: entries,
            loading: state.loading,
            busy: state.busy,
            showDemoHint: entries.isEmpty && !state.loading,
            onStartLink: () =>
                context.read<LinkedDevicesCubit>().startLinkFlow(),
            onConfirmLink: (code) async {
              await context.read<LinkedDevicesCubit>().confirmLinkCode(code);
            },
          );
        },
      ),
    );
  }

  Future<void> _startLocalLink() async {
    final linkCode =
        'local-${DateTime.now().millisecondsSinceEpoch.remainder(100000)}';
    await _showLinkCode(linkCode);
  }

  Future<void> _confirmLocalLink(String code) async {
    final value = code.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid link code')));
      return;
    }
    setState(() {
      _localEntries.insert(
        0,
        _LocalDeviceEntry(deviceName: value, lastActive: DateTime.now()),
      );
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Device linked locally')));
  }

  Future<void> _showLinkCode(String code) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link code'),
        content: SelectableText(code),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _DevicesScaffold extends StatelessWidget {
  const _DevicesScaffold({
    required this.entries,
    required this.loading,
    required this.busy,
    required this.showDemoHint,
    required this.onStartLink,
    required this.onConfirmLink,
  });

  final List<_LocalDeviceEntry> entries;
  final bool loading;
  final bool busy;
  final bool showDemoHint;
  final Future<void> Function() onStartLink;
  final Future<void> Function(String code) onConfirmLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linked devices')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showDemoHint)
                  const MaterialBanner(
                    content: Text(
                      'No linked devices were loaded. Demo mode is active.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      return ListTile(
                        leading: const Icon(Icons.laptop_mac_outlined),
                        title: Text(item.deviceName),
                        subtitle: Text(
                          'Last active: ${_formatDate(item.lastActive)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: busy
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await onStartLink();
                if (!context.mounted) {
                  return;
                }
                final controller = TextEditingController();
                final code = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm link code'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Code from other device',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text),
                        child: const Text('Link'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (code == null || !context.mounted) {
                  return;
                }
                await onConfirmLink(code);
              },
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: const Text('Link device'),
            ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _LocalDeviceEntry {
  const _LocalDeviceEntry({required this.deviceName, required this.lastActive});

  final String deviceName;
  final DateTime lastActive;
}
