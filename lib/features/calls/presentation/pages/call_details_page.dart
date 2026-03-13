import 'dart:async';

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
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
    if (Firebase.apps.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Call service is unavailable')),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirebasePaths.calls)
          .doc(widget.callId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data!;
        if (!doc.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Call details')),
            body: const Center(
              child: Text(
                'Call was not found or has already expired.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final call = _sessionFromDoc(doc);
        _ensureParticipantLabelsLoaded(call);
        final labels = _participantLabels(call);
        return InCallPage(
          callId: call.callId,
          conversationTitle: _callTitle(labels),
          participantLabels: labels,
          callType: call.type,
          initialState: call.state,
          isIncoming: _isIncomingCall(call),
        );
      },
    );
  }

  CallSession _sessionFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CallSession(
      callId: doc.id,
      participantIds: List<String>.from(
        data['participantIds'] as List? ?? const <String>[],
      ),
      type: (data['type'] as String?) == CallType.video.name
          ? CallType.video
          : CallType.voice,
      state: CallState.values.firstWhere(
        (value) => value.name == (data['state'] as String?),
        orElse: () => CallState.ringing,
      ),
      startedAt: _toDateTime(data['startedAt']) ?? DateTime.now().toUtc(),
      endedAt: _toDateTime(data['endedAt']),
      initiatorId: data['initiatorId'] as String?,
      answeredByUserId: data['answeredBy'] as String?,
    );
  }

  DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
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
