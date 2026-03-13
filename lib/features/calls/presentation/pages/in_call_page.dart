import 'dart:async';

import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/features/calls/presentation/support/webrtc_call_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class InCallPage extends StatefulWidget {
  const InCallPage({
    required this.callId,
    required this.conversationTitle,
    required this.participantLabels,
    required this.callType,
    required this.initialState,
    super.key,
    this.isIncoming = false,
  });

  final String callId;
  final String conversationTitle;
  final List<String> participantLabels;
  final CallType callType;
  final CallState initialState;
  final bool isIncoming;

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> {
  WebRtcCallController? _controller;
  Timer? _autoCloseTimer;
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant InCallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callId == widget.callId) {
      return;
    }
    _disposeController();
    _createController();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _buildUnavailableScaffold(
        message: 'Call setup is unavailable on this device right now.',
      );
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleClosePressed());
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final participants = _participants;
          final showIncomingActions =
              widget.isIncoming && controller.callState == CallState.ringing;
          final title = widget.conversationTitle.trim().isEmpty
              ? participants.first
              : widget.conversationTitle.trim();
          return Scaffold(
            backgroundColor: const Color(0xFF061221),
            body: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF0E223B), Color(0xFF05111F)],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            _topButton(
                              icon: controller.isTerminal
                                  ? Icons.close
                                  : Icons.arrow_back,
                              tooltip: controller.isTerminal ? 'Close' : 'Back',
                              onPressed: _handleClosePressed,
                            ),
                            const Spacer(),
                            _topButton(
                              icon: Icons.people_outline,
                              tooltip: 'Participants',
                              onPressed: _showParticipantsSheet,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusLabel(controller.callState),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              participants.join(' - '),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: widget.callType == CallType.video
                              ? _buildVideoStage(controller, participants.first)
                              : _buildVoiceStage(participants.first),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        child: showIncomingActions
                            ? _buildIncomingActions(controller)
                            : controller.isTerminal
                            ? _buildTerminalActions()
                            : _buildActiveControls(controller),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<String> get _participants {
    final seen = <String>{};
    final values = <String>[];
    for (final raw in widget.participantLabels) {
      final value = raw.trim();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      values.add(value);
    }
    if (values.isEmpty) {
      return const <String>['Unknown'];
    }
    return values;
  }

  void _createController() {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return;
    }
    final controller = WebRtcCallController(
      firestore: FirebaseFirestore.instance,
      callId: widget.callId,
      callType: widget.callType,
      currentUserId: currentUserId,
      isIncoming: widget.isIncoming,
      initialState: widget.initialState,
    );
    controller.addListener(_handleControllerChange);
    _controller = controller;
    unawaited(controller.initialize());
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleControllerChange);
    controller.dispose();
    _controller = null;
  }

  void _handleControllerChange() {
    if (!mounted) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final error = controller.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      controller.clearError();
    }
    if (!controller.isTerminal) {
      _autoCloseTimer?.cancel();
      return;
    }
    _autoCloseTimer ??= Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  Future<void> _handleClosePressed() async {
    final controller = _controller;
    if (controller == null) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (controller.isTerminal) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (widget.isIncoming && controller.callState == CallState.ringing) {
      await controller.rejectCall();
    } else {
      await controller.endCall();
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _acceptCall() async {
    await _controller?.acceptCall();
  }

  Future<void> _rejectCall() async {
    await _controller?.rejectCall();
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _endCall() async {
    await _controller?.endCall();
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  String _statusLabel(CallState state) {
    return switch (state) {
      CallState.ringing =>
        widget.isIncoming ? 'Incoming call...' : 'Ringing...',
      CallState.connecting => 'Connecting...',
      CallState.connected => 'In call',
      CallState.ended => 'Call ended',
      CallState.missed => 'Missed call',
      CallState.failed => 'Call failed',
    };
  }

  Widget _buildVoiceStage(String label) {
    return Center(
      child: CircleAvatar(
        radius: 112,
        backgroundColor: const Color(0xFF1A4572),
        child: Text(
          _initialFor(label),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoStage(WebRtcCallController controller, String label) {
    final previewBorder = BorderRadius.circular(20);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF102238)),
              child: controller.hasRemoteVideo
                  ? RTCVideoView(controller.remoteRenderer)
                  : _buildVideoPlaceholder(label),
            ),
          ),
        ),
        if (controller.hasLocalVideo)
          Positioned(
            right: 16,
            bottom: 16,
            child: ClipRRect(
              borderRadius: previewBorder,
              child: Container(
                width: 112,
                height: 168,
                color: const Color(0xFF0A1828),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RTCVideoView(controller.localRenderer, mirror: true),
                    if (!controller.videoEnabled)
                      const ColoredBox(
                        color: Color(0xB0000000),
                        child: Center(
                          child: Icon(
                            Icons.videocam_off,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPlaceholder(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 76,
            backgroundColor: const Color(0xFF1E4D7D),
            child: Text(
              _initialFor(label),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Waiting for video...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingActions(WebRtcCallController controller) {
    return Row(
      children: [
        Expanded(
          child: _wideActionButton(
            label: 'Decline',
            icon: Icons.call_end,
            backgroundColor: const Color(0xFFE53935),
            onPressed: controller.busy ? null : _rejectCall,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _wideActionButton(
            label: 'Accept',
            icon: Icons.call,
            backgroundColor: const Color(0xFF1B9E4B),
            onPressed: controller.busy ? null : _acceptCall,
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalActions() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close),
        label: const Text('Close'),
      ),
    );
  }

  Widget _buildActiveControls(WebRtcCallController controller) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xE0122231),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          _roundActionButton(
            icon: controller.speakerEnabled ? Icons.volume_up : Icons.hearing,
            tooltip: 'Speaker',
            isActive: controller.speakerEnabled,
            onPressed: controller.busy ? null : controller.toggleSpeaker,
          ),
          _roundActionButton(
            icon: controller.muted ? Icons.mic_off : Icons.mic,
            tooltip: 'Mute',
            isActive: !controller.muted,
            onPressed: controller.busy ? null : controller.toggleMute,
          ),
          if (widget.callType == CallType.video)
            _roundActionButton(
              icon: controller.videoEnabled
                  ? Icons.videocam
                  : Icons.videocam_off,
              tooltip: 'Camera',
              isActive: controller.videoEnabled,
              onPressed: controller.busy ? null : controller.toggleVideo,
            ),
          if (widget.callType == CallType.video)
            _roundActionButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: 'Switch camera',
              onPressed: controller.busy || !controller.canSwitchCamera
                  ? null
                  : controller.switchCamera,
            ),
          _roundActionButton(
            icon: Icons.call_end,
            tooltip: 'End call',
            backgroundColor: const Color(0xFFF44336),
            onPressed: controller.busy ? null : _endCall,
          ),
        ],
      ),
    );
  }

  Widget _roundActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isActive = true,
    Color? backgroundColor,
  }) {
    final baseColor =
        backgroundColor ??
        (isActive ? const Color(0xFF20374E) : const Color(0xFF112131));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: baseColor,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _wideActionButton({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _topButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: Colors.white,
      style: IconButton.styleFrom(backgroundColor: const Color(0x5F20374E)),
    );
  }

  void _showParticipantsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF112233),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.call, color: Colors.white),
                title: Text(
                  widget.conversationTitle,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  widget.callType == CallType.video
                      ? 'Video call'
                      : 'Voice call',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              for (final label in _participants)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF1E4D7D),
                    child: Text(
                      _initialFor(label),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _initialFor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.characters.first.toUpperCase();
  }

  Widget _buildUnavailableScaffold({required String message}) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
