import 'dart:async';

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/features/calls/presentation/bloc/calls_cubit.dart';
import 'package:chatify/features/calls/presentation/support/call_participant_label_resolver.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  late final CallParticipantLabelResolver _participantLabelResolver =
      CallParticipantLabelResolver(
        contactsRepository: getIt.isRegistered<ContactsRepository>()
            ? getIt<ContactsRepository>()
            : null,
        firestore: Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null,
      );

  bool get _hasWiredCalls =>
      getIt.isRegistered<CallsCubit>() && Firebase.apps.isNotEmpty;

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    unawaited(_loadParticipantContactLabels());
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredCalls) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calls')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Calls are unavailable until Firebase and authentication are ready.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return BlocProvider(
      create: (_) => getIt<CallsCubit>(),
      child: BlocConsumer<CallsCubit, CallsState>(
        listener: (context, state) {
          _ensureParticipantLabelsLoaded(state.calls);
          if (state.errorMessage == null) {
            return;
          }
          AppLogger.breadcrumb(
            'calls.ui.error_shown',
            action: 'ui.snackbar',
            metadata: <String, Object?>{'message': state.errorMessage},
          );
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
        },
        builder: (context, state) {
          _ensureParticipantLabelsLoaded(state.calls);
          return Scaffold(
            appBar: AppBar(title: const Text('Calls')),
            body: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.calls.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No real calls yet. Start a voice or video call from a one-to-one chat.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: state.calls.length,
                    separatorBuilder: (_, _) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final call = state.calls[index];
                      final labels = _participantLabelsForCall(call);
                      final title = _resolveCallTitle(
                        call: call,
                        participantLabels: labels,
                      );
                      final isIncoming = _isIncomingCall(call);
                      final isActionable =
                          call.state == CallState.ringing ||
                          call.state == CallState.connecting;
                      return ListTile(
                        onTap: isActionable
                            ? () => context.push(
                                '/call/${Uri.encodeComponent(call.callId)}',
                              )
                            : null,
                        leading: CircleAvatar(
                          child: Text(
                            title.trim().isEmpty
                                ? '?'
                                : title.trim()[0].toUpperCase(),
                          ),
                        ),
                        title: Text(title),
                        subtitle: Text(_subtitleForCall(call, isIncoming)),
                        trailing: Icon(
                          call.type == CallType.video
                              ? Icons.videocam
                              : Icons.call,
                          color: isActionable
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

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

  String _subtitleForCall(CallSession call, bool isIncoming) {
    final direction = isIncoming ? 'Incoming' : 'Outgoing';
    final kind = call.type == CallType.video ? 'video call' : 'voice call';
    final state = switch (call.state) {
      CallState.ringing => 'ringing',
      CallState.connecting => 'connecting',
      CallState.connected => 'connected',
      CallState.ended => 'ended',
      CallState.missed => 'missed',
      CallState.failed => 'failed',
    };
    return '$direction $kind - $state';
  }

  String _resolveCallTitle({
    required CallSession call,
    required List<String> participantLabels,
  }) {
    if (participantLabels.isEmpty) {
      return _labelForParticipantId(call.initiatorId ?? '');
    }
    if (participantLabels.length == 1) {
      return participantLabels.first;
    }
    if (participantLabels.length == 2) {
      return '${participantLabels[0]}, ${participantLabels[1]}';
    }
    return '${participantLabels[0]}, ${participantLabels[1]} +${participantLabels.length - 2}';
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
    return _participantLabelResolver.resolveLabel(
      participantId,
      currentUserId: _currentUserId,
    );
  }

  Future<void> _loadParticipantContactLabels() async {
    final didChange = await _participantLabelResolver.preloadContacts();
    if (!mounted || !didChange) {
      return;
    }
    setState(() {});
  }

  void _ensureParticipantLabelsLoaded(Iterable<CallSession> calls) {
    final currentUserId = _currentUserId;
    final participantIds = calls
        .expand((call) => call.participantIds)
        .map((participantId) => participantId.trim())
        .where(
          (participantId) =>
              participantId.isNotEmpty && participantId != currentUserId,
        )
        .toSet();
    if (participantIds.isEmpty) {
      return;
    }
    unawaited(_loadRemoteParticipantLabels(participantIds));
  }

  Future<void> _loadRemoteParticipantLabels(Iterable<String> userIds) async {
    final didChange = await _participantLabelResolver
        .ensureRemoteProfilesLoaded(userIds);
    if (!mounted || !didChange) {
      return;
    }
    setState(() {});
  }
}
