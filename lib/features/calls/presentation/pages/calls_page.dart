import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/features/calls/presentation/bloc/calls_cubit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final List<_LocalCallEntry> _localCalls = [
    const _LocalCallEntry(
      callId: 'local_call_1',
      title: 'Alice',
      subtitle: 'Yesterday, voice call',
      type: CallType.voice,
      state: CallState.ended,
    ),
    const _LocalCallEntry(
      callId: 'local_call_2',
      title: 'Backend Team',
      subtitle: 'Today, video call',
      type: CallType.video,
      state: CallState.ringing,
    ),
  ];

  bool get _hasWiredCalls =>
      getIt.isRegistered<CallsCubit>() && Firebase.apps.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredCalls) {
      return _CallsScaffold(
        entries: _localCalls,
        loading: false,
        busy: false,
        showDemoHint: true,
        onStartCall: _startLocalCall,
        onEndCall: _endLocalCall,
      );
    }

    return BlocProvider(
      create: (_) => getIt<CallsCubit>(),
      child: BlocConsumer<CallsCubit, CallsState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
        },
        builder: (context, state) {
          final entries = state.calls
              .map(
                (call) => _LocalCallEntry(
                  callId: call.callId,
                  title: call.participantIds.join(', '),
                  subtitle: '${call.type.name} call',
                  type: call.type,
                  state: call.state,
                ),
              )
              .toList();
          return _CallsScaffold(
            entries: entries,
            loading: state.loading,
            busy: state.busy,
            showDemoHint: entries.isEmpty && !state.loading,
            onStartCall: (type, participantIds) async {
              await context.read<CallsCubit>().startCall(
                participantIds: participantIds,
                type: type,
              );
            },
            onEndCall: (callId) async {
              await context.read<CallsCubit>().endCall(callId);
            },
          );
        },
      ),
    );
  }

  Future<void> _startLocalCall(
    CallType type,
    List<String> participantIds,
  ) async {
    if (participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one participant')),
      );
      return;
    }
    setState(() {
      _localCalls.insert(
        0,
        _LocalCallEntry(
          callId: 'local_call_${DateTime.now().millisecondsSinceEpoch}',
          title: participantIds.join(', '),
          subtitle: '${type.name} call',
          type: type,
          state: CallState.ringing,
        ),
      );
    });
  }

  Future<void> _endLocalCall(String callId) async {
    final index = _localCalls.indexWhere((entry) => entry.callId == callId);
    if (index < 0) {
      return;
    }
    setState(() {
      final current = _localCalls[index];
      _localCalls[index] = current.copyWith(state: CallState.ended);
    });
  }
}

class _CallsScaffold extends StatelessWidget {
  const _CallsScaffold({
    required this.entries,
    required this.loading,
    required this.busy,
    required this.showDemoHint,
    required this.onStartCall,
    required this.onEndCall,
  });

  final List<_LocalCallEntry> entries;
  final bool loading;
  final bool busy;
  final bool showDemoHint;
  final Future<void> Function(CallType type, List<String> participantIds)
  onStartCall;
  final Future<void> Function(String callId) onEndCall;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showDemoHint)
                  const MaterialBanner(
                    content: Text(
                      'No call data found yet. Demo records are shown for quick testing.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      final icon = item.type == CallType.video
                          ? Icons.videocam
                          : Icons.call;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            item.title.isEmpty
                                ? '?'
                                : item.title[0].toUpperCase(),
                          ),
                        ),
                        title: Text(item.title),
                        subtitle: Text('${item.subtitle} • ${item.state.name}'),
                        trailing: item.state == CallState.ended
                            ? Icon(icon)
                            : IconButton(
                                tooltip: 'End call',
                                icon: const Icon(Icons.call_end),
                                onPressed: () => onEndCall(item.callId),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: busy
            ? null
            : () async {
                final type = await _pickCallType(context);
                if (type == null || !context.mounted) {
                  return;
                }
                final participants = await _promptParticipants(context);
                if (participants == null || !context.mounted) {
                  return;
                }
                await onStartCall(type, participants);
              },
        child: const Icon(Icons.add_call),
      ),
    );
  }

  Future<CallType?> _pickCallType(BuildContext context) async {
    final value = await showModalBottomSheet<CallType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Voice call'),
              onTap: () => Navigator.of(context).pop(CallType.voice),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video call'),
              onTap: () => Navigator.of(context).pop(CallType.video),
            ),
          ],
        ),
      ),
    );
    return value;
  }

  Future<List<String>?> _promptParticipants(BuildContext context) async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call participants'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Participant ids',
            hintText: 'uid_1, uid_2',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) {
      return null;
    }
    final values = raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return values;
  }
}

class _LocalCallEntry {
  const _LocalCallEntry({
    required this.callId,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.state,
  });

  final String callId;
  final String title;
  final String subtitle;
  final CallType type;
  final CallState state;

  _LocalCallEntry copyWith({
    String? callId,
    String? title,
    String? subtitle,
    CallType? type,
    CallState? state,
  }) {
    return _LocalCallEntry(
      callId: callId ?? this.callId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      state: state ?? this.state,
    );
  }
}
