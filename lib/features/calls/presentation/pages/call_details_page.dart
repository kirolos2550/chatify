import 'dart:async';

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/features/calls/presentation/pages/in_call_page.dart';
import 'package:chatify/features/calls/presentation/support/call_participant_label_resolver.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class CallDetailsPage extends StatefulWidget {
  const CallDetailsPage({required this.callId, super.key});

  final String callId;

  @override
  State<CallDetailsPage> createState() => _CallDetailsPageState();
}

class _CallDetailsPageState extends State<CallDetailsPage> {
  late final CallParticipantLabelResolver _participantLabelResolver =
      CallParticipantLabelResolver(
        contactsRepository: getIt.isRegistered<ContactsRepository>()
            ? getIt<ContactsRepository>()
            : null,
        firestore: Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_loadParticipantContactLabels());
  }

  Future<void> _loadParticipantContactLabels() async {
    final didChange = await _participantLabelResolver.preloadContacts();
    if (!mounted || !didChange) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!getIt.isRegistered<CallRepository>()) {
      return const Scaffold(
        body: Center(child: Text('Call service is unavailable')),
      );
    }
    final repository = getIt<CallRepository>();
    return StreamBuilder<List<CallSession>>(
      stream: repository.watchCalls(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final call = _findCallById(snapshot.data!, widget.callId);
        if (call == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Call details')),
            body: Center(
              child: Text(
                'Call was not found or has already expired.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        _ensureParticipantLabelsLoaded(call);
        final labels = _participantLabels(call);
        return InCallPage(
          conversationTitle: _callTitle(labels),
          participantLabels: labels,
          callType: call.type,
          initialState: call.state,
          isIncoming: _isIncomingCall(call),
          onEndCall: () async {
            await repository.endCall(callId: call.callId);
          },
          onAcceptCall: () async {
            await repository.acceptCall(callId: call.callId);
          },
          onRejectCall: () async {
            await repository.rejectCall(callId: call.callId);
          },
        );
      },
    );
  }

  CallSession? _findCallById(List<CallSession> calls, String callId) {
    for (final call in calls) {
      if (call.callId == callId) {
        return call;
      }
    }
    return null;
  }

  bool _isIncomingCall(CallSession call) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }
    final initiatorId = call.initiatorId;
    if (initiatorId == null || initiatorId.isEmpty) {
      return false;
    }
    return initiatorId != currentUserId;
  }

  List<String> _participantLabels(CallSession call) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final labels = call.participantIds
        .where(
          (participantId) =>
              currentUserId == null || participantId != currentUserId,
        )
        .where((participantId) => participantId.trim().isNotEmpty)
        .map(_participantLabelForId)
        .toList(growable: false);
    if (labels.isEmpty) {
      return const ['You'];
    }
    return labels;
  }

  String _participantLabelForId(String userId) {
    return _participantLabelResolver.resolveLabel(
      userId,
      currentUserId: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  String _callTitle(List<String> labels) {
    if (labels.isEmpty) {
      return 'Call';
    }
    if (labels.length == 1) {
      return labels.first;
    }
    if (labels.length == 2) {
      return '${labels[0]}, ${labels[1]}';
    }
    return '${labels[0]}, ${labels[1]} +${labels.length - 2}';
  }

  void _ensureParticipantLabelsLoaded(CallSession call) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final participantIds = call.participantIds
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
