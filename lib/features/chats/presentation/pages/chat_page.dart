import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/data/repositories/in_memory_message_repository.dart';
import 'package:chatify/core/data/services/device_identity_service.dart';
import 'package:chatify/core/data/services/user_privacy_service.dart';
import 'package:chatify/core/crypto/crypto_engine.dart';
import 'package:chatify/core/crypto/signal_crypto_engine.dart';
import 'package:chatify/core/domain/entities/conversation.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:chatify/features/chats/domain/usecases/send_text_message_use_case.dart';
import 'package:chatify/features/chats/presentation/bloc/chat_thread_cubit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

final InMemoryMessageRepository _fallbackMessageRepository =
    InMemoryMessageRepository();

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversationId, super.key});

  final String conversationId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatThreadCubit _chatThreadCubit;
  final TextEditingController _messageController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _voicePlayer = AudioPlayer();
  StreamSubscription<Duration>? _voicePositionSubscription;
  StreamSubscription<Duration?>? _voiceDurationSubscription;
  StreamSubscription<PlayerState>? _voicePlayerStateSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _typingSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _peerPresenceSubscription;
  Timer? _typingDebounceTimer;
  bool _isMuted = false;
  bool _isBlocked = false;
  bool _isRecordingVoice = false;
  bool _typingVisibilityEnabled = true;
  bool _lastSeenVisible = true;
  bool _peerTyping = false;
  bool _peerOnline = false;
  bool _peerAllowsLastSeen = true;
  bool _isTypingPublished = false;
  DateTime? _voiceRecordingStartedAt;
  DateTime? _peerLastSeenAt;
  String? _activeVoiceMessageId;
  Duration _activeVoicePosition = Duration.zero;
  Duration _activeVoiceDuration = Duration.zero;
  bool _isVoicePlaying = false;
  _ChatTheme _chatTheme = _ChatTheme.defaultTheme;

  @override
  void initState() {
    super.initState();
    final cryptoEngine = _resolveCryptoEngine();
    final messageRepository = _resolveMessageRepository();
    final sendTextMessageUseCase = _resolveSendTextMessageUseCase(
      messageRepository,
      cryptoEngine,
    );
    _chatThreadCubit = ChatThreadCubit(
      messageRepository,
      sendTextMessageUseCase,
      cryptoEngine,
      _resolveCurrentUserId(),
    )..start(widget.conversationId);
    _attachVoicePlayerListeners();
    unawaited(_initRealtimeSignals());
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _chatThreadCubit.start(widget.conversationId);
      unawaited(_resetVoicePlayback());
      unawaited(_initRealtimeSignals());
    }
  }

  @override
  void dispose() {
    if (_isRecordingVoice) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _typingDebounceTimer?.cancel();
    _typingSubscription?.cancel();
    _peerPresenceSubscription?.cancel();
    unawaited(_setTypingState(false));
    unawaited(_setPresence(online: false));
    _voicePositionSubscription?.cancel();
    _voiceDurationSubscription?.cancel();
    _voicePlayerStateSubscription?.cancel();
    _voicePlayer.dispose();
    _messageController.dispose();
    _chatThreadCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _chatThreadCubit,
      child: BlocListener<ChatThreadCubit, ChatThreadState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage &&
            current.errorMessage != null,
        listener: (context, state) {
          final message = state.errorMessage;
          if (message == null || !mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
        child: Scaffold(
          appBar: AppBar(
            title: _buildChatTitle(),
            actions: [
              IconButton(
                tooltip: 'Voice call',
                onPressed: () => _startCall(CallType.voice),
                icon: const Icon(Icons.call_outlined),
              ),
              IconButton(
                tooltip: 'Video call',
                onPressed: () => _startCall(CallType.video),
                icon: const Icon(Icons.videocam_outlined),
              ),
              PopupMenuButton<_ChatMenuAction>(
                onSelected: _onChatMenuAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _ChatMenuAction.createGroup,
                    child: Text('Create group with this contact'),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.viewContact,
                    child: Text('View contact'),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.searchChat,
                    child: Text('Search in chat'),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.mediaLinksDocs,
                    child: Text('Media, links and docs'),
                  ),
                  PopupMenuItem(
                    value: _ChatMenuAction.toggleMute,
                    child: Text(
                      _isMuted ? 'Unmute notifications' : 'Mute notifications',
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.changeTheme,
                    child: Text('Change chat theme'),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.reportContact,
                    child: Text('Report contact'),
                  ),
                  PopupMenuItem(
                    value: _ChatMenuAction.toggleBlock,
                    child: Text(
                      _isBlocked ? 'Unblock contact' : 'Block contact',
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ChatMenuAction.clearChat,
                    child: Text('Clear chat'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              BlocBuilder<ChatThreadCubit, ChatThreadState>(
                buildWhen: (previous, current) =>
                    previous.messages != current.messages,
                builder: (context, state) => _buildPinnedMessagesBanner(state),
              ),
              Expanded(
                child: BlocBuilder<ChatThreadCubit, ChatThreadState>(
                  builder: (context, state) {
                    if (state.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state.messages.isEmpty) {
                      return const Center(
                        child: Text('No messages yet. Start the conversation.'),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final message = state.messages[index];
                        return Align(
                          alignment: message.isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _onMessageLongPress(message),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: message.isMine
                                    ? _myBubbleColor(context)
                                    : _peerBubbleColor(context),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (message.isPinned)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.push_pin_outlined,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Pinned',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (message.replyToMessageId != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Reply to ${_shortId(message.replyToMessageId!)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  _buildMessageBody(message),
                                  if (message.reactionsByUser.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: _buildMessageReactions(message),
                                    ),
                                  const SizedBox(height: 6),
                                  _buildMessageMeta(context, message),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: BlocBuilder<ChatThreadCubit, ChatThreadState>(
                    buildWhen: (previous, current) =>
                        previous.sending != current.sending ||
                        previous.replyingTo != current.replyingTo,
                    builder: (context, state) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.replyingTo != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Replying to: ${state.replyingTo!.text}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Cancel reply',
                                    onPressed: _chatThreadCubit.cancelReply,
                                  ),
                                ],
                              ),
                            ),
                          if (_isBlocked)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'You blocked this contact. Unblock to send messages.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Attach',
                                  onPressed: state.sending
                                      ? null
                                      : _openAttachmentSheet,
                                  icon: const Icon(Icons.attach_file),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    textInputAction: TextInputAction.send,
                                    decoration: const InputDecoration(
                                      hintText: 'Type message',
                                    ),
                                    onChanged: _onComposerChanged,
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _isRecordingVoice
                                      ? 'Stop recording'
                                      : 'Voice note',
                                  onPressed: state.sending
                                      ? null
                                      : _sendVoiceNote,
                                  icon: Icon(
                                    _isRecordingVoice
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_none_outlined,
                                    color: _isRecordingVoice
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton.filled(
                                  onPressed: state.sending
                                      ? null
                                      : _sendMessage,
                                  icon: state.sending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send),
                                ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTitle() {
    final subtitle = _chatSubtitleText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Conversation ${_shortId(widget.conversationId)}'),
        if (subtitle != null)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String? _chatSubtitleText() {
    if (_peerTyping) {
      return 'typing...';
    }
    if (_peerOnline) {
      return 'online';
    }
    if (_peerAllowsLastSeen && _peerLastSeenAt != null) {
      return 'last seen ${_formatLastSeen(_peerLastSeenAt!)}';
    }
    return null;
  }

  String _formatLastSeen(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$h:$m';
    }
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  }

  Widget _buildPinnedMessagesBanner(ChatThreadState state) {
    final pinned = state.messages
        .where((item) => item.isPinned && !item.isDeleted)
        .toList(growable: false);
    if (pinned.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = pinned.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pinned messages (${pinned.length}/3)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          ...visible.map(
            (message) => Row(
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Unpin',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _togglePinMessage(message),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initRealtimeSignals() async {
    _typingSubscription?.cancel();
    _peerPresenceSubscription?.cancel();
    _typingDebounceTimer?.cancel();
    _peerTyping = false;
    _peerOnline = false;
    _peerLastSeenAt = null;
    _peerAllowsLastSeen = true;
    _isTypingPublished = false;

    if (Firebase.apps.isEmpty) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }

    final privacySettings = await UserPrivacyService.loadMySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _typingVisibilityEnabled = privacySettings.typingVisibilityEnabled;
      _lastSeenVisible = privacySettings.lastSeenVisible;
    });
    await _setPresence(online: true);

    final peer = await _resolveProfileUserIdForConversation();
    if (!mounted) {
      return;
    }
    _subscribeTyping(uid);
    if (peer != null && peer != uid) {
      _subscribePeerPresence(peer);
    }
  }

  void _subscribeTyping(String currentUid) {
    _typingSubscription = FirebaseFirestore.instance
        .collection(FirebasePaths.conversations)
        .doc(widget.conversationId)
        .collection(FirebasePaths.typing)
        .snapshots()
        .listen((snapshot) {
          var peerTyping = false;
          for (final doc in snapshot.docs) {
            if (doc.id == currentUid) {
              continue;
            }
            final data = doc.data();
            if (data['isVisible'] == false) {
              continue;
            }
            if (data['isTyping'] != true) {
              continue;
            }
            final updatedAt = _toDateTimeValue(data['updatedAt']);
            if (updatedAt != null &&
                DateTime.now().toUtc().difference(updatedAt) >
                    const Duration(seconds: 8)) {
              continue;
            }
            peerTyping = true;
            break;
          }
          if (!mounted) {
            return;
          }
          setState(() => _peerTyping = peerTyping);
        });
  }

  void _subscribePeerPresence(String peerUid) {
    _peerPresenceSubscription = FirebaseFirestore.instance
        .collection(FirebasePaths.presence)
        .doc(peerUid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data() ?? const <String, dynamic>{};
          if (!mounted) {
            return;
          }
          setState(() {
            _peerOnline = data['isOnline'] == true;
            _peerAllowsLastSeen = data['showLastSeen'] is bool
                ? data['showLastSeen'] as bool
                : true;
            _peerLastSeenAt =
                _toDateTimeValue(data['lastSeenAt']) ??
                _toDateTimeValue(data['updatedAt']);
          });
        });
  }

  void _onComposerChanged(String rawValue) {
    if (_isBlocked) {
      return;
    }
    final hasContent = rawValue.trim().isNotEmpty;
    if (!hasContent) {
      _typingDebounceTimer?.cancel();
      unawaited(_setTypingState(false));
      return;
    }
    if (!_typingVisibilityEnabled) {
      return;
    }
    unawaited(_setTypingState(true));
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_setTypingState(false));
    });
  }

  Future<void> _setTypingState(bool typing) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    final effectiveTyping = typing && _typingVisibilityEnabled;
    if (_isTypingPublished == effectiveTyping && !typing) {
      return;
    }
    _isTypingPublished = effectiveTyping;
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.conversations)
          .doc(widget.conversationId)
          .collection(FirebasePaths.typing)
          .doc(uid)
          .set({
            'isTyping': effectiveTyping,
            'isVisible': _typingVisibilityEnabled,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Skip transient typing updates errors.
    }
  }

  Future<void> _setPresence({required bool online}) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.presence)
          .doc(uid)
          .set({
            'isOnline': online,
            'showLastSeen': _lastSeenVisible,
            'lastSeenAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Presence state is best-effort only.
    }
  }

  DateTime? _toDateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  Future<void> _sendMessage() async {
    if (_isBlocked) {
      _showSnack('Unblock this contact first');
      return;
    }
    final sent = await _chatThreadCubit.sendText(_messageController.text);
    if (sent && mounted) {
      _messageController.clear();
      _onComposerChanged('');
      await _setTypingState(false);
    }
  }

  Future<void> _onChatMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.createGroup:
        await _createGroupFromCurrentChat();
        break;
      case _ChatMenuAction.viewContact:
        await _viewContactInfo();
        break;
      case _ChatMenuAction.searchChat:
        await _searchInChat();
        break;
      case _ChatMenuAction.mediaLinksDocs:
        await _showMediaLinksAndDocs();
        break;
      case _ChatMenuAction.toggleMute:
        setState(() => _isMuted = !_isMuted);
        _showSnack(_isMuted ? 'Chat muted' : 'Chat unmuted');
        break;
      case _ChatMenuAction.changeTheme:
        await _changeChatTheme();
        break;
      case _ChatMenuAction.reportContact:
        await _reportContact();
        break;
      case _ChatMenuAction.toggleBlock:
        await _toggleBlockContact();
        break;
      case _ChatMenuAction.clearChat:
        await _clearChat();
        break;
    }
  }

  Future<void> _startCall(CallType type) async {
    final repository = _resolveCallRepository();
    if (repository == null) {
      _showSnack('Call service is unavailable');
      return;
    }

    final participants = await _loadConversationMembers();
    if (participants.isEmpty) {
      _showSnack('No participants found for this chat');
      return;
    }

    final result = await repository.startCall(
      participantIds: participants,
      type: type,
    );
    if (result.error == null) {
      _showSnack('${type.name} call started');
      return;
    }
    _showSnack(result.error?.message ?? 'Failed to start ${type.name} call');
  }

  Future<List<String>> _loadConversationMembers() async {
    if (Firebase.apps.isEmpty) {
      return <String>{
        _resolveCurrentUserId(),
        'peer-${widget.conversationId}',
      }.toList(growable: false);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirebasePaths.conversations)
          .doc(widget.conversationId)
          .get();
      final raw = doc.data()?['memberIds'];
      if (raw is List) {
        return raw.whereType<String>().toSet().toList(growable: false);
      }
    } catch (_) {
      // ignore and fall back below
    }
    final current = _resolveCurrentUserId();
    return <String>{current}.toList(growable: false);
  }

  Future<void> _createGroupFromCurrentChat() async {
    final repository = _resolveConversationRepository();
    if (repository == null) {
      _showSnack('Conversation service is unavailable right now');
      return;
    }

    final members = await _loadConversationMembers();
    if (!mounted) {
      return;
    }
    final currentUserId = _resolveCurrentUserId();
    final basePeers = members.where((id) => id != currentUserId).toSet();

    final titleController = TextEditingController();
    final extraController = TextEditingController();
    try {
      final payload = await showDialog<(String, String)>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create group from this chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Group title',
                  hintText: 'Project group',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: extraController,
                decoration: const InputDecoration(
                  labelText: 'Add members',
                  hintText: 'uid_2, uid_3',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((titleController.text, extraController.text)),
              child: const Text('Create'),
            ),
          ],
        ),
      );

      if (!mounted || payload == null) {
        return;
      }

      final title = payload.$1.trim();
      if (title.isEmpty) {
        _showSnack('Group title is required');
        return;
      }
      final extra = payload.$2
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      final allMembers = <String>{...basePeers, ...extra}.toList();
      if (allMembers.isEmpty) {
        _showSnack('No members found to add');
        return;
      }

      final result = await repository.createGroup(
        title: title,
        memberUserIds: allMembers,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<String>) {
        _showSnack('Group created');
        if (context.mounted) {
          context.push('/chat/${result.value}');
        }
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to create group');
    } finally {
      titleController.dispose();
      extraController.dispose();
    }
  }

  Future<void> _viewContactInfo() async {
    final profileUserId = await _resolveProfileUserIdForConversation();
    if (!mounted || profileUserId == null || profileUserId.isEmpty) {
      _showSnack('No participant info available');
      return;
    }
    context.push('/profile/$profileUserId');
  }

  Future<String?> _resolveProfileUserIdForConversation() async {
    final members = await _loadConversationMembers();
    if (members.isEmpty) {
      return null;
    }
    final currentUserId = _resolveCurrentUserId();
    final peer = members.where((id) => id != currentUserId).firstOrNull;
    return peer ?? currentUserId;
  }

  Future<void> _searchInChat() async {
    final query = await _promptMessageInput(
      title: 'Search in chat',
      initialValue: '',
      actionLabel: 'Search',
    );
    if (!mounted || query == null) {
      return;
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return;
    }

    final matches = _chatThreadCubit.state.messages
        .where((m) => m.text.toLowerCase().contains(needle))
        .toList(growable: false);
    if (matches.isEmpty) {
      _showSnack('No results found');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.separated(
          itemCount: matches.length,
          separatorBuilder: (_, _) => const Divider(height: 0),
          itemBuilder: (context, index) {
            final item = matches[index];
            return ListTile(
              title: Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_messageMeta(item)),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showMediaLinksAndDocs() async {
    final messages = _chatThreadCubit.state.messages;
    final media = messages
        .where(
          (m) => m.type == MessageType.image || m.type == MessageType.video,
        )
        .toList(growable: false);
    final docs = messages
        .where((m) => m.type == MessageType.file)
        .toList(growable: false);
    final links = <String>[];
    final linkRegex = RegExp(r'https?://\S+');
    for (final m in messages) {
      links.addAll(linkRegex.allMatches(m.text).map((e) => e.group(0)!));
    }

    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Media (${media.length})'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('Documents (${docs.length})'),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text('Links (${links.length})'),
              subtitle: links.isEmpty
                  ? null
                  : Text(
                      links.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeChatTheme() async {
    final selected = await showModalBottomSheet<_ChatTheme>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Default'),
              onTap: () => Navigator.of(context).pop(_ChatTheme.defaultTheme),
            ),
            ListTile(
              title: const Text('Emerald'),
              onTap: () => Navigator.of(context).pop(_ChatTheme.emerald),
            ),
            ListTile(
              title: const Text('Sunset'),
              onTap: () => Navigator.of(context).pop(_ChatTheme.sunset),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() => _chatTheme = selected);
  }

  Future<void> _reportContact() async {
    final reason = await _promptMessageInput(
      title: 'Report contact',
      initialValue: '',
      actionLabel: 'Submit',
    );
    if (!mounted || reason == null || reason.trim().isEmpty) {
      return;
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.length < 5) {
      _showSnack('Please provide more details in the report');
      return;
    }
    if (Firebase.apps.isEmpty) {
      _showSnack('Reports are unavailable in demo mode');
      return;
    }
    final reporterId = FirebaseAuth.instance.currentUser?.uid;
    if (reporterId == null || reporterId.isEmpty) {
      _showSnack('Sign in first to submit reports');
      return;
    }
    final targetUserId = await _resolveProfileUserIdForConversation();
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.abuseReports)
          .add({
            'type': 'contact',
            'reporterId': reporterId,
            'targetUserId': targetUserId,
            'conversationId': widget.conversationId,
            'reason': normalizedReason,
            'status': 'open',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) {
        return;
      }
      _showSnack('Report submitted');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to submit report: $error');
    }
  }

  Future<void> _toggleBlockContact() async {
    if (_isBlocked) {
      setState(() => _isBlocked = false);
      _showSnack('Contact unblocked');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block contact'),
        content: const Text(
          'You will not be able to send messages in this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _isBlocked = true);
      _showSnack('Contact blocked');
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('Delete all messages in this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final cleared = await _chatThreadCubit.clearConversation();
    if (!mounted) {
      return;
    }
    _showSnack(cleared ? 'Chat cleared' : 'Failed to clear chat');
  }

  Future<void> _openAttachmentSheet() async {
    final action = await showModalBottomSheet<_AttachmentAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.video),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.file),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Location'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentAction.location),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Contact'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.contact),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _AttachmentAction.image:
        await _sendPickedAttachment(
          type: MessageType.image,
          pickerType: FileType.image,
        );
        break;
      case _AttachmentAction.video:
        await _sendPickedAttachment(
          type: MessageType.video,
          pickerType: FileType.video,
        );
        break;
      case _AttachmentAction.file:
        await _sendPickedAttachment(
          type: MessageType.file,
          pickerType: FileType.any,
        );
        break;
      case _AttachmentAction.location:
        await _sendLocation();
        break;
      case _AttachmentAction.contact:
        await _sendContactCard();
        break;
    }
  }

  Future<void> _sendPickedAttachment({
    required MessageType type,
    required FileType pickerType,
  }) async {
    if (_isBlocked) {
      _showSnack('Unblock this contact first');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: pickerType,
      allowMultiple: false,
      withData: false,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.single;
    final downloadUrl = await _uploadAttachment(file, type);
    final payload = jsonEncode({
      'name': file.name,
      'size': file.size,
      'url': downloadUrl,
      'ext': file.extension,
    });
    final sent = await _chatThreadCubit.sendTypedMessage(
      content: payload,
      type: type,
    );
    if (sent && mounted) {
      _showSnack('${type.name} sent');
    }
  }

  Future<void> _sendLocation() async {
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final labelController = TextEditingController();
    try {
      final payload = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Send location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              TextField(
                controller: latController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
              TextField(
                controller: lngController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'label': labelController.text.trim(),
                'lat': latController.text.trim(),
                'lng': lngController.text.trim(),
              }),
              child: const Text('Send'),
            ),
          ],
        ),
      );

      if (!mounted || payload == null) {
        return;
      }
      final sent = await _chatThreadCubit.sendTypedMessage(
        content: jsonEncode(payload),
        type: MessageType.system,
      );
      if (sent && mounted) {
        _showSnack('Location sent');
      }
    } finally {
      latController.dispose();
      lngController.dispose();
      labelController.dispose();
    }
  }

  Future<void> _sendContactCard() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    try {
      final payload = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Send contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'name': nameController.text.trim(),
                'phone': phoneController.text.trim(),
              }),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (!mounted || payload == null) {
        return;
      }
      final sent = await _chatThreadCubit.sendTypedMessage(
        content: jsonEncode(payload),
        type: MessageType.system,
      );
      if (sent && mounted) {
        _showSnack('Contact sent');
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _sendVoiceNote() async {
    if (_isBlocked) {
      _showSnack('Unblock this contact first');
      return;
    }
    if (_isRecordingVoice) {
      await _stopAndSendVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnack('Microphone permission is required');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = p.join(tempDir.path, fileName);
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = true;
        _voiceRecordingStartedAt = DateTime.now();
      });
      _showSnack('Recording started. Tap again to send.');
    } catch (_) {
      _showSnack('Failed to start recording');
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    try {
      final filePath = await _audioRecorder.stop();
      if (!mounted) {
        return;
      }

      final startedAt = _voiceRecordingStartedAt;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordingStartedAt = null;
      });

      if (filePath == null || filePath.isEmpty) {
        _showSnack('Recording canceled');
        return;
      }

      final extension = p.extension(filePath).replaceFirst('.', '');
      final fileName = p.basename(filePath);
      final durationSec = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds;
      final downloadUrl = await _uploadFileFromPath(
        filePath: filePath,
        fileName: fileName,
        extension: extension,
        type: MessageType.voice,
      );
      final payload = jsonEncode({
        'name': fileName,
        'durationSec': durationSec,
        'url': downloadUrl,
      });

      final sent = await _chatThreadCubit.sendTypedMessage(
        content: payload,
        type: MessageType.voice,
      );
      if (sent && mounted) {
        _showSnack('Voice note sent');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordingStartedAt = null;
      });
      _showSnack('Failed to send voice note');
    }
  }

  void _attachVoicePlayerListeners() {
    _voicePositionSubscription = _voicePlayer.positionStream.listen((position) {
      if (!mounted || _activeVoiceMessageId == null) {
        return;
      }
      setState(() {
        _activeVoicePosition = position;
      });
    });

    _voiceDurationSubscription = _voicePlayer.durationStream.listen((duration) {
      if (!mounted || _activeVoiceMessageId == null || duration == null) {
        return;
      }
      setState(() {
        _activeVoiceDuration = duration;
      });
    });

    _voicePlayerStateSubscription = _voicePlayer.playerStateStream.listen((
      state,
    ) {
      if (!mounted) {
        return;
      }
      final completed = state.processingState == ProcessingState.completed;
      setState(() {
        _isVoicePlaying = state.playing && !completed;
        if (completed) {
          _activeVoicePosition = Duration.zero;
        }
      });
      if (completed) {
        unawaited(_voicePlayer.seek(Duration.zero));
      }
    });
  }

  Future<void> _resetVoicePlayback() async {
    try {
      await _voicePlayer.stop();
    } catch (_) {
      // no-op
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _activeVoiceMessageId = null;
      _activeVoicePosition = Duration.zero;
      _activeVoiceDuration = Duration.zero;
      _isVoicePlaying = false;
    });
  }

  Future<void> _toggleVoiceNotePlayback(
    ChatMessageView message,
    Map<String, Object?>? payload,
  ) async {
    final isActive = _activeVoiceMessageId == message.id;
    if (!isActive) {
      final prepared = await _prepareVoicePlayback(
        message: message,
        payload: payload,
      );
      if (!prepared) {
        return;
      }
      await _voicePlayer.play();
      return;
    }

    if (_isVoicePlaying) {
      await _voicePlayer.pause();
      return;
    }

    if (_voicePlayer.processingState == ProcessingState.completed) {
      await _voicePlayer.seek(Duration.zero);
    }
    await _voicePlayer.play();
  }

  Future<void> _seekVoiceNotePlayback({
    required ChatMessageView message,
    required Map<String, Object?>? payload,
    required Duration target,
    bool playAfterSeek = false,
  }) async {
    final wasPlaying = _isVoicePlaying;
    var isActive = _activeVoiceMessageId == message.id;
    if (!isActive) {
      final prepared = await _prepareVoicePlayback(
        message: message,
        payload: payload,
      );
      if (!prepared) {
        return;
      }
      isActive = true;
    }

    if (!isActive) {
      return;
    }

    final maxDuration =
        _activeVoiceMessageId == message.id &&
            _activeVoiceDuration > Duration.zero
        ? _activeVoiceDuration
        : _resolveVoiceDuration(payload);
    final clamped = _clampDuration(target, maxDuration);
    await _voicePlayer.seek(clamped);

    if (!mounted) {
      return;
    }
    setState(() {
      _activeVoicePosition = clamped;
    });

    if (playAfterSeek || wasPlaying) {
      await _voicePlayer.play();
    }
  }

  Future<bool> _prepareVoicePlayback({
    required ChatMessageView message,
    required Map<String, Object?>? payload,
  }) async {
    final url = payload?['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      _showSnack('Voice note file is unavailable');
      return false;
    }

    try {
      final expectedDuration = _resolveVoiceDuration(payload);
      await _voicePlayer.stop();
      final loadedDuration = await _voicePlayer.setUrl(url);
      if (!mounted) {
        return false;
      }
      setState(() {
        _activeVoiceMessageId = message.id;
        _activeVoicePosition = Duration.zero;
        _activeVoiceDuration = loadedDuration ?? expectedDuration;
      });
      return true;
    } catch (_) {
      _showSnack('Failed to load this voice note');
      return false;
    }
  }

  Duration _resolveVoiceDuration(Map<String, Object?>? payload) {
    final durationValue = payload?['durationSec'];
    if (durationValue is int && durationValue >= 0) {
      return Duration(seconds: durationValue);
    }
    if (durationValue is String) {
      final parsed = int.tryParse(durationValue);
      if (parsed != null && parsed >= 0) {
        return Duration(seconds: parsed);
      }
    }

    final fallbackDuration = _voicePlayer.duration;
    if (fallbackDuration != null && fallbackDuration > Duration.zero) {
      return fallbackDuration;
    }

    return const Duration(seconds: 1);
  }

  Duration _clampDuration(Duration value, Duration maxDuration) {
    if (value < Duration.zero) {
      return Duration.zero;
    }
    if (value > maxDuration) {
      return maxDuration;
    }
    return value;
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<String?> _uploadAttachment(PlatformFile file, MessageType type) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final bytes = file.bytes;
    final filePath = file.path;
    if (uid == null ||
        (bytes == null && (filePath == null || filePath.isEmpty))) {
      return null;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final ref = FirebaseStorage.instance.ref().child(
        'media/$uid/${widget.conversationId}/$timestamp-$safeName',
      );
      final metadata = SettableMetadata(
        contentType: _contentTypeFor(type, file.extension),
      );
      if (bytes != null) {
        await ref.putData(bytes, metadata);
      } else {
        await ref.putFile(File(filePath!), metadata);
      }
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _uploadFileFromPath({
    required String filePath,
    required String fileName,
    required String extension,
    required MessageType type,
  }) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return null;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final ref = FirebaseStorage.instance.ref().child(
        'media/$uid/${widget.conversationId}/$timestamp-$safeName',
      );
      await ref.putFile(
        File(filePath),
        SettableMetadata(contentType: _contentTypeFor(type, extension)),
      );
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  String _contentTypeFor(MessageType type, String? extension) {
    switch (type) {
      case MessageType.image:
        return 'image/${extension ?? 'jpeg'}';
      case MessageType.video:
        return 'video/${extension ?? 'mp4'}';
      case MessageType.file:
        return 'application/octet-stream';
      case MessageType.voice:
        return 'audio/aac';
      default:
        return 'text/plain';
    }
  }

  Future<void> _onMessageLongPress(ChatMessageView message) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Reply'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.reply),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.forward_outlined),
                  title: const Text('Forward'),
                  onTap: () =>
                      Navigator.of(context).pop(_MessageAction.forward),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('React'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.react),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: Icon(
                    message.isStarred ? Icons.star : Icons.star_outline,
                  ),
                  title: Text(
                    message.isStarred
                        ? 'Remove from starred'
                        : 'Add to starred',
                  ),
                  onTap: () => Navigator.of(context).pop(_MessageAction.star),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: Icon(
                    message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(
                    message.isPinned ? 'Unpin message' : 'Pin message',
                  ),
                  onTap: () => Navigator.of(context).pop(_MessageAction.pin),
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Info'),
                onTap: () => Navigator.of(context).pop(_MessageAction.info),
              ),
              if (message.isMine &&
                  !message.isDeleted &&
                  (message.type == MessageType.text ||
                      message.type == MessageType.system))
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.edit),
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.delete),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _MessageAction.reply:
        _chatThreadCubit.startReply(message);
        break;
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text));
        if (mounted) {
          _showSnack('Message copied');
        }
        break;
      case _MessageAction.info:
        await _showMessageInfo(message);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.delete:
        await _handleDeleteMessage(message);
        break;
      case _MessageAction.forward:
        await _forwardMessage(message);
        break;
      case _MessageAction.react:
        await _reactToMessage(message);
        break;
      case _MessageAction.star:
        await _toggleStarMessage(message);
        break;
      case _MessageAction.pin:
        await _togglePinMessage(message);
        break;
    }
  }

  Future<void> _reactToMessage(ChatMessageView message) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove my reaction'),
              onTap: () => Navigator.of(context).pop(''),
            ),
            _buildReactionOption(context, '👍'),
            _buildReactionOption(context, '❤️'),
            _buildReactionOption(context, '😂'),
            _buildReactionOption(context, '😮'),
            _buildReactionOption(context, '😢'),
            _buildReactionOption(context, '🙏'),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    final success = await _chatThreadCubit.setMessageReaction(
      message: message,
      emoji: selected.isEmpty ? null : selected,
    );
    if (success && mounted) {
      _showSnack(selected.isEmpty ? 'Reaction removed' : 'Reaction updated');
    }
  }

  ListTile _buildReactionOption(BuildContext context, String emoji) {
    return ListTile(
      title: Text(emoji, style: const TextStyle(fontSize: 24)),
      onTap: () => Navigator.of(context).pop(emoji),
    );
  }

  Future<void> _toggleStarMessage(ChatMessageView message) async {
    final success = await _chatThreadCubit.toggleMessageStar(message);
    if (success && mounted) {
      _showSnack(
        message.isStarred
            ? 'Removed from starred messages'
            : 'Added to starred messages',
      );
    }
  }

  Future<void> _togglePinMessage(ChatMessageView message) async {
    final success = await _chatThreadCubit.toggleMessagePin(message);
    if (success && mounted) {
      _showSnack(message.isPinned ? 'Message unpinned' : 'Message pinned');
    }
  }

  Future<void> _editMessage(ChatMessageView message) async {
    final updatedText = await _promptMessageInput(
      title: 'Edit message',
      initialValue: message.text,
      actionLabel: 'Save',
    );
    if (!mounted || updatedText == null) {
      return;
    }
    final success = await _chatThreadCubit.editMessage(
      message: message,
      newText: updatedText,
    );
    if (success && mounted) {
      _showSnack('Message updated');
    }
  }

  Future<void> _forwardMessage(ChatMessageView message) async {
    final targetConversationId = await _pickForwardConversationId();
    if (!mounted || targetConversationId == null) {
      return;
    }
    final success = await _chatThreadCubit.forwardMessage(
      message: message,
      targetConversationId: targetConversationId,
    );
    if (success && mounted) {
      _showSnack('Message forwarded');
    }
  }

  Future<void> _handleDeleteMessage(ChatMessageView message) async {
    final scope = await _askDeleteMessageScope(message);
    if (!mounted || scope == null) {
      return;
    }

    final deleted = switch (scope) {
      _DeleteScope.forMe => await _chatThreadCubit.deleteMessageForMe(message),
      _DeleteScope.forEveryone =>
        await _chatThreadCubit.deleteMessageForEveryone(message),
    };
    if (!mounted || !deleted) {
      return;
    }
    final label = scope == _DeleteScope.forMe
        ? 'Message deleted for you'
        : 'Message deleted for everyone';
    _showSnack(label);
  }

  Future<_DeleteScope?> _askDeleteMessageScope(ChatMessageView message) async {
    if (!message.isMine) {
      return _DeleteScope.forMe;
    }

    return showModalBottomSheet<_DeleteScope>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Delete for me'),
              onTap: () => Navigator.of(context).pop(_DeleteScope.forMe),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Delete for everyone'),
              onTap: () => Navigator.of(context).pop(_DeleteScope.forEveryone),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickForwardConversationId() async {
    final repository = _resolveConversationRepository();
    if (repository == null) {
      _showSnack('Conversation service is unavailable right now');
      return null;
    }

    final conversations = await repository.watchConversations().first;
    final options = conversations
        .where((conversation) => conversation.id != widget.conversationId)
        .toList();
    if (options.isEmpty) {
      _showSnack('No target conversation available');
      return null;
    }
    if (!mounted) {
      return null;
    }

    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final conversation = options[index];
              return ListTile(
                title: Text(_conversationTitle(conversation)),
                subtitle: Text(conversation.id),
                onTap: () => Navigator.of(context).pop(conversation.id),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showMessageInfo(ChatMessageView message) async {
    final sentAt = message.sentAt.toString();
    final editedAt = message.editedAt?.toString() ?? '-';
    final deletedAt = message.deletedForAllAt?.toString() ?? '-';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message info'),
        content: SelectableText(
          'Message ID: ${message.id}\n'
          'Sender ID: ${message.senderId}\n'
          'Sent at: $sentAt\n'
          'Edited at: $editedAt\n'
          'Deleted at: $deletedAt\n'
          'Reply to: ${message.replyToMessageId ?? '-'}\n'
          'Starred: ${message.isStarred}\n'
          'Pinned: ${message.isPinned}\n'
          'Reactions: ${message.reactionsByUser.values.join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptMessageInput({
    required String title,
    required String initialValue,
    required String actionLabel,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            minLines: 1,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Message text'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(actionLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _buildMessageBody(ChatMessageView message) {
    final payload = _tryDecodePayload(message.text);

    switch (message.type) {
      case MessageType.image:
      case MessageType.video:
      case MessageType.file:
        final icon = switch (message.type) {
          MessageType.image => Icons.image_outlined,
          MessageType.video => Icons.videocam_outlined,
          _ => Icons.description_outlined,
        };
        final title = payload?['name']?.toString() ?? message.type.name;
        final url = payload?['url']?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (url != null && url.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      case MessageType.voice:
        return _buildVoiceNoteBody(message, payload);
      case MessageType.system:
        final lat = payload?['lat']?.toString();
        final lng = payload?['lng']?.toString();
        final name = payload?['name']?.toString();
        final phone = payload?['phone']?.toString();
        if (lat != null && lng != null) {
          return Text('Location: $lat, $lng');
        }
        if (name != null && phone != null) {
          return Text('Contact: $name ($phone)');
        }
        return Text(message.text);
      case MessageType.text:
      case MessageType.videoNote:
        return Text(message.text);
    }
  }

  Widget _buildMessageReactions(ChatMessageView message) {
    final counts = <String, int>{};
    for (final emoji in message.reactionsByUser.values) {
      counts.update(emoji, (value) => value + 1, ifAbsent: () => 1);
    }
    final sorted = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sorted
          .map(
            (entry) => Chip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              label: Text('${entry.key} ${entry.value}'),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildVoiceNoteBody(
    ChatMessageView message,
    Map<String, Object?>? payload,
  ) {
    final hasUrl = (payload?['url']?.toString().trim().isNotEmpty ?? false);
    final isActive = _activeVoiceMessageId == message.id;
    final duration = isActive && _activeVoiceDuration > Duration.zero
        ? _activeVoiceDuration
        : _resolveVoiceDuration(payload);
    final position = isActive
        ? _clampDuration(_activeVoicePosition, duration)
        : Duration.zero;
    final maxMs = math.max(duration.inMilliseconds.toDouble(), 1.0);
    final rawValue = isActive ? position.inMilliseconds.toDouble() : 0.0;
    final sliderValue = rawValue.clamp(0, maxMs).toDouble();

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: hasUrl
                    ? () => _toggleVoiceNotePlayback(message, payload)
                    : null,
                icon: Icon(
                  isActive && _isVoicePlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                tooltip: isActive && _isVoicePlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 2),
              const Expanded(child: Text('Voice note')),
            ],
          ),
          Slider(
            value: sliderValue,
            min: 0,
            max: maxMs,
            onChanged: hasUrl
                ? (value) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _activeVoiceMessageId = message.id;
                      _activeVoicePosition = Duration(
                        milliseconds: value.round(),
                      );
                      _activeVoiceDuration = duration;
                    });
                  }
                : null,
            onChangeEnd: hasUrl
                ? (value) {
                    unawaited(
                      _seekVoiceNotePlayback(
                        message: message,
                        payload: payload,
                        target: Duration(milliseconds: value.round()),
                        playAfterSeek: true,
                      ),
                    );
                  }
                : null,
          ),
          Text(
            '${_formatDuration(position)} / ${_formatDuration(duration)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!hasUrl)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Audio file is unavailable in this environment',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Map<String, Object?>? _tryDecodePayload(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {
      // not a JSON payload
    }
    return null;
  }

  String _messageMeta(ChatMessageView message) {
    final h = message.sentAt.hour.toString().padLeft(2, '0');
    final m = message.sentAt.minute.toString().padLeft(2, '0');
    final edited = message.editedAt != null ? ' - edited' : '';
    final kind = message.type == MessageType.text
        ? ''
        : ' - ${message.type.name}';
    final starred = message.isStarred ? ' - starred' : '';
    final pinned = message.isPinned ? ' - pinned' : '';
    return '$h:$m$kind$edited$starred$pinned';
  }

  Widget _buildMessageMeta(BuildContext context, ChatMessageView message) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final meta = _messageMeta(message);
    if (!message.isMine) {
      return Text(meta, style: textStyle);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(meta, style: textStyle),
        const SizedBox(width: 4),
        Icon(
          _ackIconData(message.ack),
          size: 14,
          color: _ackIconColor(context, message.ack),
        ),
      ],
    );
  }

  IconData _ackIconData(ChatMessageAck ack) {
    return switch (ack) {
      ChatMessageAck.sent => Icons.done,
      ChatMessageAck.delivered => Icons.done_all,
      ChatMessageAck.read => Icons.done_all,
    };
  }

  Color _ackIconColor(BuildContext context, ChatMessageAck ack) {
    return switch (ack) {
      ChatMessageAck.read => const Color(0xFF2196F3),
      ChatMessageAck.sent || ChatMessageAck.delivered => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };
  }

  Color _myBubbleColor(BuildContext context) {
    return switch (_chatTheme) {
      _ChatTheme.defaultTheme => Theme.of(context).colorScheme.primaryContainer,
      _ChatTheme.emerald => const Color(0xFFD5F2E3),
      _ChatTheme.sunset => const Color(0xFFFFE3D1),
    };
  }

  Color _peerBubbleColor(BuildContext context) {
    return switch (_chatTheme) {
      _ChatTheme.defaultTheme => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
      _ChatTheme.emerald => const Color(0xFFF2FBF6),
      _ChatTheme.sunset => const Color(0xFFFFF5ED),
    };
  }

  String _shortId(String id) {
    if (id.length <= 8) {
      return id;
    }
    return '${id.substring(0, 8)}...';
  }

  String _conversationTitle(Conversation conversation) {
    final title = conversation.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return conversation.type == ConversationType.group
        ? 'Group ${_shortId(conversation.id)}'
        : 'Direct chat ${_shortId(conversation.id)}';
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  MessageRepository _resolveMessageRepository() {
    if (Firebase.apps.isEmpty) {
      return _fallbackMessageRepository;
    }
    try {
      return getIt<MessageRepository>();
    } catch (_) {
      return _fallbackMessageRepository;
    }
  }

  SendTextMessageUseCase _resolveSendTextMessageUseCase(
    MessageRepository repository,
    CryptoEngine cryptoEngine,
  ) {
    if (Firebase.apps.isNotEmpty) {
      try {
        return getIt<SendTextMessageUseCase>();
      } catch (_) {
        // Fallback to local implementation below.
      }
    }
    return SendTextMessageUseCase(
      repository,
      cryptoEngine,
      getIt<DeviceIdentityService>(),
      getIt<Uuid>(),
    );
  }

  CryptoEngine _resolveCryptoEngine() {
    if (getIt.isRegistered<CryptoEngine>()) {
      try {
        return getIt<CryptoEngine>();
      } catch (_) {
        // Fall back to the lightweight implementation below.
      }
    }
    return SignalCryptoEngine();
  }

  String _resolveCurrentUserId() {
    if (Firebase.apps.isEmpty) {
      return 'local-debug-user';
    }
    try {
      return getIt<FirebaseAuth>().currentUser?.uid ?? 'local-debug-user';
    } catch (_) {
      return 'local-debug-user';
    }
  }

  ConversationRepository? _resolveConversationRepository() {
    if (!getIt.isRegistered<ConversationRepository>()) {
      return null;
    }
    try {
      return getIt<ConversationRepository>();
    } catch (_) {
      return null;
    }
  }

  CallRepository? _resolveCallRepository() {
    if (!getIt.isRegistered<CallRepository>()) {
      return null;
    }
    try {
      return getIt<CallRepository>();
    } catch (_) {
      return null;
    }
  }
}

enum _MessageAction {
  reply,
  copy,
  info,
  edit,
  delete,
  forward,
  react,
  star,
  pin,
}

enum _DeleteScope { forMe, forEveryone }

enum _ChatTheme { defaultTheme, emerald, sunset }

enum _ChatMenuAction {
  createGroup,
  viewContact,
  searchChat,
  mediaLinksDocs,
  toggleMute,
  changeTheme,
  reportContact,
  toggleBlock,
  clearChat,
}

enum _AttachmentAction { image, video, file, location, contact }
