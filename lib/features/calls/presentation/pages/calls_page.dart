import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/features/calls/presentation/bloc/calls_cubit.dart';
import 'package:chatify/features/calls/presentation/pages/in_call_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      participantLabels: <String>['Alice'],
      type: CallType.voice,
      state: CallState.ended,
    ),
    const _LocalCallEntry(
      callId: 'local_call_2',
      title: 'Backend Team',
      subtitle: 'Today, video call',
      participantLabels: <String>['Alice', 'Mohamed', 'Rania'],
      type: CallType.video,
      state: CallState.ringing,
      isIncoming: true,
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
        onAcceptCall: _acceptLocalCall,
        onRejectCall: _rejectLocalCall,
      );
    }

    return BlocProvider(
      create: (_) => getIt<CallsCubit>(),
      child: BlocConsumer<CallsCubit, CallsState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            AppLogger.breadcrumb(
              'calls.ui.error_shown',
              action: 'ui.snackbar',
              metadata: <String, Object?>{'message': state.errorMessage},
            );
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
        },
        builder: (context, state) {
          final entries = state.calls.map((call) {
            final participantLabels = _participantLabelsForCall(call);
            return _LocalCallEntry(
              callId: call.callId,
              title: _resolveCallTitle(
                call: call,
                participantLabels: participantLabels,
              ),
              subtitle:
                  '${_isIncomingCall(call) ? 'Incoming' : 'Outgoing'} ${call.type.name} call',
              participantLabels: participantLabels,
              type: call.type,
              state: call.state,
              isIncoming: _isIncomingCall(call),
            );
          }).toList();
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
            onAcceptCall: (callId) async {
              await context.read<CallsCubit>().acceptCall(callId);
            },
            onRejectCall: (callId) async {
              await context.read<CallsCubit>().rejectCall(callId);
            },
          );
        },
      ),
    );
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  bool _isIncomingCall(CallSession call) {
    final current = _currentUserId;
    if (current == null || current.isEmpty) {
      return false;
    }
    final initiatorId = call.initiatorId;
    if (initiatorId == null || initiatorId.isEmpty) {
      return false;
    }
    return initiatorId != current;
  }

  String _resolveCallTitle({
    required CallSession call,
    required List<String> participantLabels,
  }) {
    if (call.participantIds.length > 2 || participantLabels.length > 1) {
      return 'Group call';
    }
    if (participantLabels.isNotEmpty) {
      return participantLabels.first;
    }
    return _labelForParticipantId(call.initiatorId ?? '');
  }

  List<String> _participantLabelsForCall(CallSession call) {
    final current = _currentUserId;
    final others = call.participantIds
        .where((participant) => current == null || participant != current)
        .where((participant) => participant.trim().isNotEmpty)
        .map(_labelForParticipantId)
        .toList(growable: false);
    if (others.isEmpty && current != null && current.isNotEmpty) {
      return const ['You'];
    }
    return others;
  }

  String _labelForParticipantId(String participantId) {
    final value = participantId.trim();
    if (value.isEmpty) {
      return 'Unknown';
    }
    if (value.length <= 16) {
      return value;
    }
    return '${value.substring(0, 16)}...';
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
      final labels = participantIds.map(_labelForParticipantId).toList();
      _localCalls.insert(
        0,
        _LocalCallEntry(
          callId: 'local_call_${DateTime.now().millisecondsSinceEpoch}',
          title: labels.length > 1 ? 'Group call' : labels.first,
          subtitle: '${type.name} call',
          participantLabels: labels,
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

  Future<void> _acceptLocalCall(String callId) async {
    final index = _localCalls.indexWhere((entry) => entry.callId == callId);
    if (index < 0) {
      return;
    }
    setState(() {
      final current = _localCalls[index];
      _localCalls[index] = current.copyWith(state: CallState.connected);
    });
  }

  Future<void> _rejectLocalCall(String callId) async {
    final index = _localCalls.indexWhere((entry) => entry.callId == callId);
    if (index < 0) {
      return;
    }
    setState(() {
      final current = _localCalls[index];
      _localCalls[index] = current.copyWith(state: CallState.missed);
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
    required this.onAcceptCall,
    required this.onRejectCall,
  });

  final List<_LocalCallEntry> entries;
  final bool loading;
  final bool busy;
  final bool showDemoHint;
  final Future<void> Function(CallType type, List<String> participantIds)
  onStartCall;
  final Future<void> Function(String callId) onEndCall;
  final Future<void> Function(String callId) onAcceptCall;
  final Future<void> Function(String callId) onRejectCall;

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
                      final canAnswerIncoming =
                          item.isIncoming && item.state == CallState.ringing;
                      final canEndCall =
                          item.state == CallState.ringing ||
                          item.state == CallState.connecting ||
                          item.state == CallState.connected;
                      return ListTile(
                        onTap: () => _openInCall(context, item),
                        leading: CircleAvatar(
                          child: Text(
                            item.title.isEmpty
                                ? '?'
                                : item.title[0].toUpperCase(),
                          ),
                        ),
                        title: Text(item.title),
                        subtitle: Text('${item.subtitle} - ${item.state.name}'),
                        trailing: canAnswerIncoming
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Answer',
                                    icon: const Icon(
                                      Icons.call,
                                      color: Colors.green,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => onAcceptCall(item.callId),
                                  ),
                                  IconButton(
                                    tooltip: 'Decline',
                                    icon: const Icon(
                                      Icons.call_end,
                                      color: Colors.red,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => onRejectCall(item.callId),
                                  ),
                                ],
                              )
                            : canEndCall
                            ? IconButton(
                                tooltip: 'End call',
                                icon: const Icon(Icons.call_end),
                                onPressed: busy
                                    ? null
                                    : () => onEndCall(item.callId),
                              )
                            : Icon(icon),
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

  Future<void> _openInCall(BuildContext context, _LocalCallEntry item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InCallPage(
          conversationTitle: item.title,
          participantLabels: item.participantLabels,
          callType: item.type,
          initialState: item.state,
          isIncoming: item.isIncoming,
          onEndCall: () => onEndCall(item.callId),
          onAcceptCall: item.isIncoming
              ? () => onAcceptCall(item.callId)
              : null,
          onRejectCall: item.isIncoming
              ? () => onRejectCall(item.callId)
              : null,
        ),
      ),
    );
  }
}

class _LocalCallEntry {
  const _LocalCallEntry({
    required this.callId,
    required this.title,
    required this.subtitle,
    required this.participantLabels,
    required this.type,
    required this.state,
    this.isIncoming = false,
  });

  final String callId;
  final String title;
  final String subtitle;
  final List<String> participantLabels;
  final CallType type;
  final CallState state;
  final bool isIncoming;

  _LocalCallEntry copyWith({
    String? callId,
    String? title,
    String? subtitle,
    List<String>? participantLabels,
    CallType? type,
    CallState? state,
    bool? isIncoming,
  }) {
    return _LocalCallEntry(
      callId: callId ?? this.callId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      participantLabels: participantLabels ?? this.participantLabels,
      type: type ?? this.type,
      state: state ?? this.state,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}
