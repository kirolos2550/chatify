import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:flutter/material.dart';

class InCallPage extends StatefulWidget {
  const InCallPage({
    required this.conversationTitle,
    required this.participantLabels,
    required this.callType,
    required this.initialState,
    super.key,
    this.isIncoming = false,
    this.onEndCall,
    this.onAcceptCall,
    this.onRejectCall,
  });

  final String conversationTitle;
  final List<String> participantLabels;
  final CallType callType;
  final CallState initialState;
  final bool isIncoming;
  final Future<void> Function()? onEndCall;
  final Future<void> Function()? onAcceptCall;
  final Future<void> Function()? onRejectCall;

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> {
  late CallState _callState;
  late bool _videoEnabled;
  bool _speakerEnabled = true;
  bool _muted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _callState = widget.initialState;
    _videoEnabled = widget.callType == CallType.video;
  }

  bool get _isEnded =>
      _callState == CallState.ended ||
      _callState == CallState.missed ||
      _callState == CallState.failed;

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
      return const ['Unknown'];
    }
    return values;
  }

  String get _statusLabel {
    return switch (_callState) {
      CallState.ringing =>
        widget.isIncoming ? 'Incoming call...' : 'Ringing...',
      CallState.connecting => 'Connecting...',
      CallState.connected => 'In call',
      CallState.ended => 'Call ended',
      CallState.missed => 'Missed call',
      CallState.failed => 'Call failed',
    };
  }

  Future<void> _acceptCall() async {
    if (_busy || _isEnded) {
      return;
    }
    setState(() => _busy = true);
    await widget.onAcceptCall?.call();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _callState = CallState.connected;
    });
  }

  Future<void> _rejectCall() async {
    if (_busy || _isEnded) {
      return;
    }
    setState(() => _busy = true);
    await widget.onRejectCall?.call();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _callState = CallState.missed;
    });
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _endCall() async {
    if (_busy) {
      return;
    }
    if (_isEnded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    await widget.onEndCall?.call();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _callState = CallState.ended;
    });
    Navigator.of(context).pop();
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12243A),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline, color: Colors.white),
              title: const Text(
                'Participants',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _participants.join(', '),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            ListTile(
              leading: Icon(
                _videoEnabled ? Icons.videocam_off_outlined : Icons.videocam,
                color: Colors.white,
              ),
              title: Text(
                _videoEnabled ? 'Turn off video' : 'Turn on video',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _videoEnabled = !_videoEnabled);
              },
            ),
            ListTile(
              leading: Icon(
                _speakerEnabled ? Icons.hearing_disabled : Icons.volume_up,
                color: Colors.white,
              ),
              title: Text(
                _speakerEnabled ? 'Disable speaker' : 'Enable speaker',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _speakerEnabled = !_speakerEnabled);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final participantCount = _participants.length;
    final showIncomingActions =
        widget.isIncoming && _callState == CallState.ringing;
    return Scaffold(
      backgroundColor: const Color(0xFF071526),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D2036), Color(0xFF061221)],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _CallBackdropPainter())),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _roundTopActionButton(
                        icon: Icons.open_in_full,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      _roundTopActionButton(
                        icon: Icons.group_add_outlined,
                        onPressed: _showMoreSheet,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(
                        widget.conversationTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusLabel,
                        style: const TextStyle(
                          fontSize: 19,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        participantCount == 1
                            ? _participants.first
                            : _participants.take(4).join(' - '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: Center(child: _buildCallAvatar())),
                if (showIncomingActions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 42),
                    child: Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.call_end,
                            backgroundColor: const Color(0xFFE53935),
                            onPressed: _busy ? null : _rejectCall,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.call,
                            backgroundColor: const Color(0xFF1B9E4B),
                            onPressed: _busy ? null : _acceptCall,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE1122230),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.more_horiz,
                            onPressed: _showMoreSheet,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: _videoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            isActive: _videoEnabled,
                            onPressed: () {
                              if (_busy || _isEnded) {
                                return;
                              }
                              setState(() => _videoEnabled = !_videoEnabled);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: _speakerEnabled
                                ? Icons.volume_up
                                : Icons.hearing_disabled,
                            isActive: _speakerEnabled,
                            onPressed: () {
                              if (_busy || _isEnded) {
                                return;
                              }
                              setState(
                                () => _speakerEnabled = !_speakerEnabled,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: _muted ? Icons.mic_off : Icons.mic,
                            isActive: !_muted,
                            onPressed: () {
                              if (_busy || _isEnded) {
                                return;
                              }
                              setState(() => _muted = !_muted);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.call_end,
                            backgroundColor: const Color(0xFFF50057),
                            onPressed: _busy ? null : _endCall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallAvatar() {
    final participants = _participants;
    if (participants.length == 1) {
      return CircleAvatar(
        radius: 118,
        backgroundColor: const Color(0xFF1A4572),
        child: Text(
          _initialFor(participants.first),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 74,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    final visible = participants.take(3).toList(growable: false);
    return SizedBox(
      width: 260,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: 26.0 + (index * 64),
              top: index == 1 ? 0 : 26,
              child: CircleAvatar(
                radius: 62,
                backgroundColor: Color.lerp(
                  const Color(0xFF1A4572),
                  const Color(0xFF2C6CAB),
                  (index + 1) / (visible.length + 1),
                ),
                child: Text(
                  _initialFor(visible[index]),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundTopActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF20384A),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color backgroundColor = const Color(0xFF2E4658),
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF3D5F78) : backgroundColor,
        shape: BoxShape.circle,
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  String _initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _CallBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    const spacing = 72.0;
    for (var y = 16.0; y < size.height; y += spacing) {
      for (var x = 14.0; x < size.width; x += spacing) {
        final rect = Rect.fromCenter(
          center: Offset(x, y),
          width: 20,
          height: 20,
        );
        canvas.drawOval(rect, paint);
        canvas.drawLine(Offset(x - 12, y + 12), Offset(x + 12, y - 12), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
