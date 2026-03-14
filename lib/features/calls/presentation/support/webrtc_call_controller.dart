import 'dart:async';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebRtcCallController extends ChangeNotifier {
  WebRtcCallController({
    required FirebaseFirestore firestore,
    required CallCandidateTransport candidateTransport,
    required this.callId,
    required this.callType,
    required this.currentUserId,
    required this.isIncoming,
    required CallState initialState,
  }) : _firestore = firestore,
       _candidateTransport = candidateTransport,
       _callState = initialState,
       _videoEnabled = callType == CallType.video;

  final FirebaseFirestore _firestore;
  final CallCandidateTransport _candidateTransport;
  final String callId;
  final CallType callType;
  final String currentUserId;
  final bool isIncoming;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallState _callState;
  bool _videoEnabled;
  bool _speakerEnabled = true;
  bool _muted = false;
  bool _busy = false;
  bool _initialized = false;
  bool _accepted = false;
  bool _creatingAnswer = false;
  bool _createdOffer = false;
  bool _createdAnswer = false;
  bool _appliedRemoteOffer = false;
  bool _appliedRemoteAnswer = false;
  bool _connectedMarked = false;
  bool _hasLocalVideo = false;
  bool _hasRemoteVideo = false;
  String? _errorMessage;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<RemoteIceCandidate>? _remoteCandidatesSubscription;
  final Set<String> _handledRemoteCandidateKeys = <String>{};
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];

  CallState get callState => _callState;
  bool get videoEnabled => _videoEnabled;
  bool get speakerEnabled => _speakerEnabled;
  bool get muted => _muted;
  bool get busy => _busy;
  bool get hasLocalVideo => _hasLocalVideo;
  bool get hasRemoteVideo => _hasRemoteVideo;
  bool get canSwitchCamera => _localVideoTrack != null;
  String? get errorMessage => _errorMessage;
  bool get isTerminal =>
      _callState == CallState.ended ||
      _callState == CallState.missed ||
      _callState == CallState.failed;

  DocumentReference<Map<String, dynamic>> get _callDoc =>
      _firestore.collection(FirebasePaths.calls).doc(callId);

  MediaStreamTrack? get _audioTrack {
    final tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) {
      return null;
    }
    return tracks.first;
  }

  MediaStreamTrack? get _localVideoTrack {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) {
      return null;
    }
    return tracks.first;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _accepted = !isIncoming;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await _applySpeakerphone();
    _listenToCallDocument();
    if (!isIncoming && !isTerminal) {
      await _startOutgoingCall();
    }
  }

  Future<void> acceptCall() async {
    if (_busy || _accepted || isTerminal) {
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _ensureLocalMedia();
      await _ensureRemoteCandidateListener();
      _accepted = true;
      _setCallState(CallState.connecting);
      await _callDoc.set({
        'state': CallState.connecting.name,
        'answeredBy': currentUserId,
        'answeredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final snapshot = await _callDoc.get();
      final offer = _sessionDescriptionFromData(snapshot.data()?['offer']);
      if (offer != null) {
        await _createAnswerFromOffer(offer);
      }
    } on _CallSetupException catch (error) {
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      _errorMessage = 'Failed to connect this call.';
      AppLogger.error(
        'Failed to accept call',
        error,
        stackTrace,
        event: 'calls.webrtc.accept.failure',
        action: 'calls.webrtc.accept',
        metadata: <String, Object?>{'callId': callId},
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> rejectCall() async {
    if (_busy || isTerminal) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      await _callDoc.set({
        'state': CallState.missed.name,
        'declinedBy': currentUserId,
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _setCallState(CallState.missed);
    } catch (error, stackTrace) {
      _errorMessage = 'Failed to reject this call.';
      AppLogger.error(
        'Failed to reject call',
        error,
        stackTrace,
        event: 'calls.webrtc.reject.failure',
        action: 'calls.webrtc.reject',
        metadata: <String, Object?>{'callId': callId},
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> endCall() async {
    if (_busy || isTerminal) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      await _callDoc.set({
        'state': CallState.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': currentUserId,
      }, SetOptions(merge: true));
      _setCallState(CallState.ended);
    } catch (error, stackTrace) {
      _errorMessage = 'Failed to end this call.';
      AppLogger.error(
        'Failed to end call',
        error,
        stackTrace,
        event: 'calls.webrtc.end.failure',
        action: 'calls.webrtc.end',
        metadata: <String, Object?>{'callId': callId},
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleMute() async {
    final track = _audioTrack;
    if (_busy || isTerminal || track == null) {
      return;
    }
    final next = !_muted;
    track.enabled = !next;
    try {
      await Helper.setMicrophoneMute(next, track);
    } catch (_) {
      // Fallback to track.enabled only.
    }
    _muted = next;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (_busy || isTerminal) {
      return;
    }
    _speakerEnabled = !_speakerEnabled;
    await _applySpeakerphone();
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    final track = _localVideoTrack;
    if (_busy || isTerminal || callType != CallType.video || track == null) {
      return;
    }
    _videoEnabled = !_videoEnabled;
    track.enabled = _videoEnabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final track = _localVideoTrack;
    if (_busy || isTerminal || track == null) {
      return;
    }
    try {
      await Helper.switchCamera(track);
    } catch (error, stackTrace) {
      _errorMessage = 'Failed to switch camera.';
      AppLogger.error(
        'Failed to switch camera',
        error,
        stackTrace,
        event: 'calls.webrtc.camera_switch.failure',
        action: 'calls.webrtc.camera_switch',
        metadata: <String, Object?>{'callId': callId},
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_disposeAsync());
    super.dispose();
  }

  Future<void> _disposeAsync() async {
    await _callSubscription?.cancel();
    await _remoteCandidatesSubscription?.cancel();
    await _candidateTransport.dispose();
    try {
      final tracks = _localStream?.getTracks() ?? const <MediaStreamTrack>[];
      for (final track in tracks) {
        track.stop();
      }
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {
      // Best effort cleanup.
    }
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  void _listenToCallDocument() {
    _callSubscription = _callDoc.snapshots().listen(
      (snapshot) {
        if (!snapshot.exists) {
          _setFailure('This call is no longer available.', updateRemote: false);
          return;
        }
        final data = snapshot.data() ?? const <String, dynamic>{};
        final remoteState = _callStateFromName(data['state'] as String?);
        if (remoteState != null) {
          if (remoteState == CallState.connecting &&
              _callState == CallState.ringing) {
            _setCallState(CallState.connecting);
          } else if (remoteState == CallState.connected &&
              _callState != CallState.connected) {
            _setCallState(CallState.connected);
          } else if (remoteState == CallState.ended ||
              remoteState == CallState.missed ||
              remoteState == CallState.failed) {
            _setCallState(remoteState);
          }
        }

        if (!isIncoming && !_appliedRemoteAnswer) {
          final answer = _sessionDescriptionFromData(data['answer']);
          if (answer != null) {
            unawaited(_applyRemoteAnswer(answer));
          }
        }

        if (isIncoming && _accepted && !_createdAnswer) {
          final offer = _sessionDescriptionFromData(data['offer']);
          if (offer != null) {
            unawaited(_createAnswerFromOffer(offer));
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _errorMessage = 'Call sync failed.';
        AppLogger.error(
          'Call document listener failed',
          error,
          stackTrace,
          event: 'calls.webrtc.document.failure',
          action: 'calls.webrtc.document',
          metadata: <String, Object?>{'callId': callId},
        );
        notifyListeners();
      },
    );
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _ensureLocalMedia();
      await _ensureRemoteCandidateListener();
      final offer = await _peerConnection!.createOffer(_sdpConstraints());
      await _peerConnection!.setLocalDescription(offer);
      await _callDoc.set({
        'offer': _sessionDescriptionMap(offer),
        'answer': null,
        'state': CallState.ringing.name,
      }, SetOptions(merge: true));
      _createdOffer = true;
    } on _CallSetupException catch (error) {
      await _setFailure(error.message, updateRemote: true);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to start outgoing call',
        error,
        stackTrace,
        event: 'calls.webrtc.start.failure',
        action: 'calls.webrtc.start',
        metadata: <String, Object?>{'callId': callId},
      );
      await _setFailure('Failed to start this call.', updateRemote: true);
    }
  }

  Future<void> _ensureLocalMedia() async {
    await _ensurePermissions();
    await _ensurePeerConnection();
    await _ensureLocalStream();
    await _addLocalTracks();
  }

  Future<void> _ensurePermissions() async {
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      throw _CallSetupException(
        microphone.isPermanentlyDenied
            ? 'Microphone permission is blocked. Enable it in app settings.'
            : 'Microphone permission is required for calls.',
      );
    }
    if (callType != CallType.video) {
      return;
    }
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      throw _CallSetupException(
        camera.isPermanentlyDenied
            ? 'Camera permission is blocked. Enable it in app settings.'
            : 'Camera permission is required for video calls.',
      );
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) {
      return;
    }
    final connection = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, Object>>[
        <String, Object>{
          'urls': <String>[
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    }, <String, dynamic>{});
    connection.onIceCandidate = (candidate) {
      unawaited(_storeLocalCandidate(candidate));
    };
    connection.onTrack = (event) {
      unawaited(_attachRemoteTrack(event));
    };
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_markConnected());
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(
          _setFailure('The call connection failed.', updateRemote: true),
        );
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting &&
          _callState == CallState.ringing) {
        _setCallState(CallState.connecting);
      }
    };
    connection.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        unawaited(_markConnected());
        return;
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(
          _setFailure('The call connection failed.', updateRemote: true),
        );
      }
    };
    _peerConnection = connection;
  }

  Future<void> _ensureLocalStream() async {
    if (_localStream != null) {
      return;
    }
    final stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': true,
      'video': callType == CallType.video
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': <String, int>{'ideal': 1280},
              'height': <String, int>{'ideal': 720},
            }
          : false,
    });
    _localStream = stream;
    _hasLocalVideo = stream.getVideoTracks().isNotEmpty;
    if (_hasLocalVideo) {
      localRenderer.srcObject = stream;
    }
    if (!_hasLocalVideo) {
      _videoEnabled = false;
    }
  }

  Future<void> _addLocalTracks() async {
    if (_peerConnection == null || _localStream == null) {
      return;
    }
    final senders = await _peerConnection!.getSenders();
    if (senders.isNotEmpty) {
      return;
    }
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  Future<void> _ensureRemoteCandidateListener() async {
    if (_remoteCandidatesSubscription != null) {
      return;
    }
    _remoteCandidatesSubscription = _candidateTransport
        .watchRemoteCandidates()
        .listen(
          (event) {
            if (!_handledRemoteCandidateKeys.add(event.key)) {
              return;
            }
            if (_canApplyRemoteCandidates) {
              unawaited(_peerConnection?.addCandidate(event.candidate));
            } else {
              _pendingRemoteCandidates.add(event.candidate);
            }
          },
      onError: (Object error, StackTrace stackTrace) {
        _errorMessage = 'Network signaling failed.';
        AppLogger.error(
          'Remote candidate listener failed',
          error,
          stackTrace,
          event: 'calls.webrtc.candidates.failure',
          action: 'calls.webrtc.candidates',
          metadata: <String, Object?>{'callId': callId},
        );
        notifyListeners();
      },
    );
  }

  Future<void> _createAnswerFromOffer(RTCSessionDescription offer) async {
    if (_creatingAnswer || _createdAnswer) {
      return;
    }
    _creatingAnswer = true;
    try {
      await _ensureLocalMedia();
      await _ensureRemoteCandidateListener();
      if (!_appliedRemoteOffer) {
        await _peerConnection!.setRemoteDescription(offer);
        _appliedRemoteOffer = true;
        await _flushPendingRemoteCandidates();
      }
      final answer = await _peerConnection!.createAnswer(_sdpConstraints());
      await _peerConnection!.setLocalDescription(answer);
      await _callDoc.set({
        'answer': _sessionDescriptionMap(answer),
        'state': CallState.connecting.name,
      }, SetOptions(merge: true));
      _createdAnswer = true;
      _setCallState(CallState.connecting);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to create answer',
        error,
        stackTrace,
        event: 'calls.webrtc.answer.failure',
        action: 'calls.webrtc.answer',
        metadata: <String, Object?>{'callId': callId},
      );
      await _setFailure('Failed to connect this call.', updateRemote: true);
    } finally {
      _creatingAnswer = false;
      notifyListeners();
    }
  }

  Future<void> _applyRemoteAnswer(RTCSessionDescription answer) async {
    if (_appliedRemoteAnswer || _peerConnection == null || !_createdOffer) {
      return;
    }
    try {
      await _peerConnection!.setRemoteDescription(answer);
      _appliedRemoteAnswer = true;
      await _flushPendingRemoteCandidates();
      _setCallState(CallState.connecting);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to apply remote answer',
        error,
        stackTrace,
        event: 'calls.webrtc.answer_apply.failure',
        action: 'calls.webrtc.answer_apply',
        metadata: <String, Object?>{'callId': callId},
      );
      await _setFailure('Failed to connect this call.', updateRemote: true);
    }
  }

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    final stream = event.streams.isNotEmpty
        ? event.streams.first
        : (_remoteStream ?? await createLocalMediaStream('remote-$callId'));
    _remoteStream = stream;
    if (event.streams.isEmpty &&
        !stream.getTracks().any((track) => track.id == event.track.id)) {
      await stream.addTrack(event.track, addToNative: false);
    }
    _hasRemoteVideo =
        stream.getVideoTracks().isNotEmpty || event.track.kind == 'video';
    remoteRenderer.srcObject = stream;
    await _markConnected();
    notifyListeners();
  }

  Future<void> _storeLocalCandidate(RTCIceCandidate candidate) async {
    try {
      await _candidateTransport.sendLocalCandidate(candidate);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to store local ICE candidate',
        error,
        stackTrace,
        event: 'calls.webrtc.local_candidate.failure',
        action: 'calls.webrtc.local_candidate',
        metadata: <String, Object?>{'callId': callId},
      );
    }
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (_peerConnection == null || !_canApplyRemoteCandidates) {
      return;
    }
    while (_pendingRemoteCandidates.isNotEmpty) {
      final candidate = _pendingRemoteCandidates.removeAt(0);
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {
        // Keep going; a single malformed candidate should not kill the call.
      }
    }
  }

  Future<void> _markConnected() async {
    if (_connectedMarked || isTerminal) {
      return;
    }
    _connectedMarked = true;
    _setCallState(CallState.connected);
    try {
      await _callDoc.set({
        'state': CallState.connected.name,
      }, SetOptions(merge: true));
    } catch (_) {
      // UI state can remain connected even if the status write races.
    }
  }

  Future<void> _setFailure(String message, {required bool updateRemote}) async {
    if (isTerminal) {
      return;
    }
    _errorMessage = message;
    _setCallState(CallState.failed);
    if (!updateRemote) {
      return;
    }
    try {
      await _callDoc.set({
        'state': CallState.failed.name,
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort status propagation.
    }
  }

  Future<void> _applySpeakerphone() async {
    try {
      await Helper.setSpeakerphoneOn(_speakerEnabled);
    } catch (_) {
      // Audio routing is best-effort on devices that do not expose it.
    }
  }

  bool get _canApplyRemoteCandidates =>
      isIncoming ? _appliedRemoteOffer : _appliedRemoteAnswer;

  void _setCallState(CallState next) {
    if (_callState == next) {
      return;
    }
    _callState = next;
    notifyListeners();
  }

  CallState? _callStateFromName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    for (final state in CallState.values) {
      if (state.name == value.trim()) {
        return state;
      }
    }
    return null;
  }

  RTCSessionDescription? _sessionDescriptionFromData(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final sdp = raw['sdp']?.toString();
    final type = raw['type']?.toString();
    if (sdp == null || sdp.trim().isEmpty || type == null || type.isEmpty) {
      return null;
    }
    return RTCSessionDescription(sdp, type);
  }

  Map<String, String?> _sessionDescriptionMap(RTCSessionDescription value) {
    return <String, String?>{'sdp': value.sdp, 'type': value.type};
  }

  Map<String, dynamic> _sdpConstraints() {
    return <String, dynamic>{
      'mandatory': <String, bool>{
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': callType == CallType.video,
      },
      'optional': <Object>[],
    };
  }
}

class _CallSetupException implements Exception {
  const _CallSetupException(this.message);

  final String message;
}

RTCIceCandidate? _iceCandidateFromMap(Map<String, dynamic> data) {
  final candidate = data['candidate']?.toString();
  if (candidate == null || candidate.trim().isEmpty) {
    return null;
  }
  final sdpMid = data['sdpMid']?.toString() ?? data['sdp_mid']?.toString();
  final rawIndex = data['sdpMLineIndex'] ?? data['sdp_mline_index'];
  final sdpMLineIndex = rawIndex is int ? rawIndex : int.tryParse('$rawIndex');
  return RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
}

String _candidateKey(RTCIceCandidate candidate) {
  final mid = candidate.sdpMid ?? '';
  final lineIndex = candidate.sdpMLineIndex?.toString() ?? '';
  final value = candidate.candidate ?? '';
  return '$mid|$lineIndex|$value';
}

class RemoteIceCandidate {
  const RemoteIceCandidate(this.candidate, {required this.key});

  final RTCIceCandidate candidate;
  final String key;
}

abstract class CallCandidateTransport {
  Stream<RemoteIceCandidate> watchRemoteCandidates();

  Future<void> sendLocalCandidate(RTCIceCandidate candidate);

  Future<void> dispose();
}

class FirestoreCandidateTransport implements CallCandidateTransport {
  FirestoreCandidateTransport({
    required FirebaseFirestore firestore,
    required String callId,
    required bool isIncoming,
    required String currentUserId,
  }) : _firestore = firestore,
       _callId = callId,
       _isIncoming = isIncoming,
       _currentUserId = currentUserId;

  final FirebaseFirestore _firestore;
  final String _callId;
  final bool _isIncoming;
  final String _currentUserId;

  DocumentReference<Map<String, dynamic>> get _callDoc =>
      _firestore.collection(FirebasePaths.calls).doc(_callId);

  CollectionReference<Map<String, dynamic>> get _localCandidates =>
      _callDoc.collection(
        _isIncoming
            ? FirebasePaths.calleeCandidates
            : FirebasePaths.callerCandidates,
      );

  CollectionReference<Map<String, dynamic>> get _remoteCandidates =>
      _callDoc.collection(
        _isIncoming
            ? FirebasePaths.callerCandidates
            : FirebasePaths.calleeCandidates,
      );

  @override
  Stream<RemoteIceCandidate> watchRemoteCandidates() {
    return _remoteCandidates.snapshots().expand((snapshot) {
      return snapshot.docs.map((doc) {
        final candidate = _iceCandidateFromMap(doc.data());
        if (candidate == null) {
          return null;
        }
        return RemoteIceCandidate(candidate, key: doc.id);
      }).whereType<RemoteIceCandidate>();
    });
  }

  @override
  Future<void> sendLocalCandidate(RTCIceCandidate candidate) async {
    final value = candidate.candidate?.trim();
    if (value == null || value.isEmpty) {
      return;
    }
    await _localCandidates.add(<String, Object?>{
      'candidate': value,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'authorId': _currentUserId,
    });
  }

  @override
  Future<void> dispose() async {}
}

class SupabaseCandidateTransport implements CallCandidateTransport {
  SupabaseCandidateTransport({
    required SupabaseClient client,
    required String callId,
    required bool isIncoming,
    required String currentUserId,
    String tableName = 'call_ice_candidates',
    String schema = 'public',
  }) : _client = client,
       _callId = callId,
       _currentUserId = currentUserId,
       _localRole = isIncoming ? 'callee' : 'caller',
       _tableName = tableName,
       _schema = schema;

  final SupabaseClient _client;
  final String _callId;
  final String _currentUserId;
  final String _localRole;
  final String _tableName;
  final String _schema;
  final StreamController<RemoteIceCandidate> _controller =
      StreamController<RemoteIceCandidate>.broadcast();
  RealtimeChannel? _channel;
  bool _subscribed = false;
  bool _disposed = false;

  @override
  Stream<RemoteIceCandidate> watchRemoteCandidates() {
    _ensureSubscribed();
    return _controller.stream;
  }

  @override
  Future<void> sendLocalCandidate(RTCIceCandidate candidate) async {
    final value = candidate.candidate?.trim();
    if (value == null || value.isEmpty) {
      return;
    }
    await _client.from(_tableName).insert(<String, Object?>{
      'call_id': _callId,
      'role': _localRole,
      'author_id': _currentUserId,
      'candidate': value,
      'sdp_mid': candidate.sdpMid,
      'sdp_mline_index': candidate.sdpMLineIndex,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final channel = _channel;
    if (channel != null) {
      await _client.removeChannel(channel);
      _channel = null;
    }
    await _controller.close();
  }

  void _ensureSubscribed() {
    if (_subscribed || _disposed) {
      return;
    }
    _subscribed = true;
    _channel = _client.channel('call-ice:$_callId');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: _schema,
          table: _tableName,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: _callId,
          ),
          callback: (payload) {
            _handleRow(payload.newRecord);
          },
        )
        .subscribe();
    unawaited(_fetchExisting());
  }

  Future<void> _fetchExisting() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _client.from(_tableName).select().eq('call_id', _callId),
      );
      for (final row in rows) {
        _handleRow(row);
      }
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
    }
  }

  void _handleRow(Map<String, dynamic> row) {
    if (_disposed) {
      return;
    }
    final role = row['role']?.toString();
    if (role == _localRole) {
      return;
    }
    final authorId = row['author_id']?.toString();
    if (authorId != null && authorId == _currentUserId) {
      return;
    }
    final candidate = _iceCandidateFromMap(row);
    if (candidate == null) {
      return;
    }
    final key = row['id']?.toString() ?? _candidateKey(candidate);
    _controller.add(RemoteIceCandidate(candidate, key: key));
  }
}
