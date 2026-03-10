import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/log_share_service.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

final InMemoryMessageRepository _fallbackMessageRepository =
    InMemoryMessageRepository();
const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://uhovvyhmfqogjrayqigl.supabase.co',
);
const String _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_qW4G6ek9jzbPtw1Fe3e8TQ_9IhYLBwy',
);
const String _supabaseStorageBucket = String.fromEnvironment(
  'SUPABASE_STORAGE_BUCKET',
  defaultValue: 'chat-media',
);
const bool _enableFirebaseStorageUploadFallback = bool.fromEnvironment(
  'ENABLE_FIREBASE_STORAGE_UPLOAD_FALLBACK',
  defaultValue: false,
);

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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _peerProfileSubscription;
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
  bool _sharingLogs = false;
  String? _lastUploadFailureReason;
  DateTime? _voiceRecordingStartedAt;
  DateTime? _peerLastSeenAt;
  String? _activeVoiceMessageId;
  Duration _activeVoicePosition = Duration.zero;
  Duration _activeVoiceDuration = Duration.zero;
  bool _isVoicePlaying = false;
  _ChatTheme _chatTheme = _ChatTheme.defaultTheme;
  String _conversationTitle = '';
  bool _isGroupConversation = false;
  DateTime? _conversationCreatedAt;
  List<String> _conversationMemberIds = const <String>[];
  final Map<String, Future<String?>> _resolvedAttachmentUrlCache =
      <String, Future<String?>>{};

  @override
  void initState() {
    super.initState();
    _conversationTitle = _bootstrapConversationTitle();
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
      _peerProfileSubscription?.cancel();
      _conversationTitle = _bootstrapConversationTitle();
      _isGroupConversation = false;
      _conversationCreatedAt = null;
      _conversationMemberIds = const <String>[];
      _resolvedAttachmentUrlCache.clear();
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
    _peerProfileSubscription?.cancel();
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
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<_ChatMenuAction>>[];
                  if (!_isGroupConversation) {
                    items.add(
                      PopupMenuItem(
                        value: _ChatMenuAction.createGroup,
                        child: Text(
                          _tr(
                            en: 'Create group with this contact',
                            ar: 'إنشاء مجموعة مع جهة الاتصال',
                          ),
                        ),
                      ),
                    );
                    items.add(
                      PopupMenuItem(
                        value: _ChatMenuAction.viewContact,
                        child: Text(
                          _tr(en: 'View contact', ar: 'عرض جهة الاتصال'),
                        ),
                      ),
                    );
                  } else {
                    items.add(
                      PopupMenuItem(
                        value: _ChatMenuAction.viewContact,
                        child: Text(
                          _tr(en: 'Group info', ar: 'معلومات المجموعة'),
                        ),
                      ),
                    );
                  }
                  items.addAll([
                    PopupMenuItem(
                      value: _ChatMenuAction.searchChat,
                      child: Text(
                        _tr(en: 'Search in chat', ar: 'بحث في الدردشة'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.mediaLinksDocs,
                      child: Text(
                        _tr(
                          en: 'Media, links and docs',
                          ar: 'الوسائط والروابط والمستندات',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.toggleMute,
                      child: Text(
                        _isMuted
                            ? _tr(
                                en: 'Unmute notifications',
                                ar: 'إلغاء كتم الإشعارات',
                              )
                            : _tr(
                                en: 'Mute notifications',
                                ar: 'كتم الإشعارات',
                              ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.changeTheme,
                      child: Text(
                        _tr(en: 'Change chat theme', ar: 'تغيير سمة الدردشة'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.reportContact,
                      child: Text(
                        _tr(
                          en: _isGroupConversation
                              ? 'Report group'
                              : 'Report contact',
                          ar: _isGroupConversation
                              ? 'الإبلاغ عن المجموعة'
                              : 'الإبلاغ عن جهة الاتصال',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.toggleBlock,
                      child: Text(
                        _isBlocked
                            ? _tr(
                                en: _isGroupConversation
                                    ? 'Unblock group'
                                    : 'Unblock contact',
                                ar: _isGroupConversation
                                    ? 'إلغاء حظر المجموعة'
                                    : 'إلغاء حظر جهة الاتصال',
                              )
                            : _tr(
                                en: _isGroupConversation
                                    ? 'Block group'
                                    : 'Block contact',
                                ar: _isGroupConversation
                                    ? 'حظر المجموعة'
                                    : 'حظر جهة الاتصال',
                              ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.clearChat,
                      child: Text(_tr(en: 'Clear chat', ar: 'مسح الدردشة')),
                    ),
                    PopupMenuItem(
                      value: _ChatMenuAction.exportDebugLogs,
                      child: Text(
                        _sharingLogs
                            ? 'Preparing debug logs...'
                            : 'Export debug logs',
                      ),
                    ),
                  ]);
                  return items;
                },
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
        Text(_conversationTitle),
        if (subtitle != null)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String? _chatSubtitleText() {
    if (_isGroupConversation) {
      final count = _conversationMemberIds.length;
      if (count <= 0) {
        return null;
      }
      return _tr(en: '$count members', ar: '$count أعضاء');
    }
    if (_peerTyping) {
      return _tr(en: 'typing...', ar: 'يكتب...');
    }
    if (_peerOnline) {
      return _tr(en: 'online', ar: 'متصل الآن');
    }
    if (_peerAllowsLastSeen && _peerLastSeenAt != null) {
      return _tr(
        en: 'last seen ${_formatLastSeen(_peerLastSeenAt!)}',
        ar: 'آخر ظهور ${_formatLastSeen(_peerLastSeenAt!)}',
      );
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

    await _loadConversationMetadata();
    final peer = _isGroupConversation
        ? null
        : await _resolveProfileUserIdForConversation();
    if (!mounted) {
      return;
    }
    unawaited(_refreshConversationTitle(peerUserId: peer));
    _subscribeTyping(uid);
    if (!_isGroupConversation && peer != null && peer != uid) {
      _subscribePeerPresence(peer);
      _subscribePeerProfile(peer);
      return;
    }
    _peerPresenceSubscription?.cancel();
    _peerProfileSubscription?.cancel();
  }

  Future<void> _loadConversationMetadata() async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirebasePaths.conversations)
          .doc(widget.conversationId)
          .get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final members = _toStringList(data['memberIds']);
      final type = (data['type'] as String?)?.trim().toLowerCase();
      final isGroup = type == 'group' || members.length > 2;
      final createdAt = _toDateTimeValue(data['createdAt']);
      if (!mounted) {
        return;
      }
      setState(() {
        _isGroupConversation = isGroup;
        _conversationMemberIds = members;
        _conversationCreatedAt = createdAt;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGroupConversation = false;
        _conversationMemberIds = const <String>[];
        _conversationCreatedAt = null;
      });
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
        if (_isGroupConversation) {
          _showSnack(
            _tr(
              en: 'This chat is already a group conversation',
              ar: 'هذه الدردشة مجموعة بالفعل',
            ),
          );
          break;
        }
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
        _showSnack(
          _isMuted
              ? _tr(en: 'Chat muted', ar: 'تم كتم الدردشة')
              : _tr(en: 'Chat unmuted', ar: 'تم إلغاء كتم الدردشة'),
        );
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
      case _ChatMenuAction.exportDebugLogs:
        await _exportDebugLogs();
        break;
    }
  }

  Future<void> _exportDebugLogs() async {
    if (_sharingLogs) {
      return;
    }
    if (mounted) {
      setState(() => _sharingLogs = true);
    }
    final result = await shareLatestDebugLogs(action: 'chat.logs.share');
    if (!mounted) {
      return;
    }
    setState(() => _sharingLogs = false);
    _showSnack(result.message);
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
    if (_conversationMemberIds.isNotEmpty) {
      return _conversationMemberIds.toList(growable: false);
    }
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
        final members = raw.whereType<String>().toSet().toList(growable: false);
        if (mounted) {
          setState(() => _conversationMemberIds = members);
        }
        return members;
      }
    } catch (_) {
      // ignore and fall back below
    }
    final current = _resolveCurrentUserId();
    return <String>{current}.toList(growable: false);
  }

  Future<void> _refreshConversationTitle({String? peerUserId}) async {
    final fallbackTitle = _defaultConversationTitle();
    if (Firebase.apps.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() => _conversationTitle = fallbackTitle);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirebasePaths.conversations)
          .doc(widget.conversationId)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final explicitTitle = (data['title'] as String?)?.trim();
      if (explicitTitle != null && explicitTitle.isNotEmpty) {
        if (mounted) {
          setState(() => _conversationTitle = explicitTitle);
        }
        return;
      }

      final isGroup = (data['type'] as String?) == 'group';
      if (isGroup) {
        if (mounted) {
          setState(
            () => _conversationTitle = _tr(
              en: 'Group ${_shortId(widget.conversationId)}',
              ar: 'مجموعة ${_shortId(widget.conversationId)}',
            ),
          );
        }
        return;
      }

      final currentUserId = _resolveCurrentUserId();
      final candidatePeer =
          peerUserId ??
          _toStringList(
            data['memberIds'],
          ).firstWhere((id) => id != currentUserId, orElse: () => '');
      if (candidatePeer.isEmpty) {
        if (mounted) {
          setState(() => _conversationTitle = fallbackTitle);
        }
        return;
      }

      final peerSnapshot = await FirebaseFirestore.instance
          .collection(FirebasePaths.users)
          .doc(candidatePeer)
          .get();
      final peerData = peerSnapshot.data() ?? const <String, dynamic>{};
      final peerName = (peerData['displayName'] as String?)?.trim();
      final peerPhone = (peerData['phone'] as String?)?.trim();
      final resolvedPeerTitle = (peerName != null && peerName.isNotEmpty)
          ? peerName
          : peerPhone;
      if (mounted) {
        setState(
          () => _conversationTitle =
              (resolvedPeerTitle == null || resolvedPeerTitle.isEmpty)
              ? fallbackTitle
              : resolvedPeerTitle,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _conversationTitle = fallbackTitle);
    }
  }

  void _subscribePeerProfile(String peerUid) {
    _peerProfileSubscription?.cancel();
    _peerProfileSubscription = FirebaseFirestore.instance
        .collection(FirebasePaths.users)
        .doc(peerUid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data() ?? const <String, dynamic>{};
          final name = (data['displayName'] as String?)?.trim();
          final phone = (data['phone'] as String?)?.trim();
          final title = (name != null && name.isNotEmpty) ? name : phone;
          if (!mounted || title == null || title.isEmpty) {
            return;
          }
          setState(() => _conversationTitle = title);
        });
  }

  List<String> _toStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList(growable: false);
  }

  Future<void> _createGroupFromCurrentChat() async {
    final repository = _resolveConversationRepository();
    if (repository == null) {
      _showSnack(
        _tr(
          en: 'Conversation service is unavailable right now',
          ar: 'خدمة المحادثات غير متاحة حالياً',
        ),
      );
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
          title: Text(
            _tr(
              en: 'Create group from this chat',
              ar: 'إنشاء مجموعة من هذه الدردشة',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: _tr(en: 'Group title', ar: 'اسم المجموعة'),
                  hintText: _tr(en: 'Project group', ar: 'مجموعة المشروع'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: extraController,
                decoration: InputDecoration(
                  labelText: _tr(en: 'Add members', ar: 'إضافة أعضاء'),
                  hintText: _tr(en: 'uid_2, uid_3', ar: 'uid_2, uid_3'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_tr(en: 'Cancel', ar: 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((titleController.text, extraController.text)),
              child: Text(_tr(en: 'Create', ar: 'إنشاء')),
            ),
          ],
        ),
      );

      if (!mounted || payload == null) {
        return;
      }

      final title = payload.$1.trim();
      if (title.isEmpty) {
        _showSnack(
          _tr(en: 'Group title is required', ar: 'اسم المجموعة مطلوب'),
        );
        return;
      }
      final extra = payload.$2
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      final allMembers = <String>{...basePeers, ...extra}.toList();
      if (allMembers.isEmpty) {
        _showSnack(
          _tr(en: 'No members found to add', ar: 'لا يوجد أعضاء لإضافتهم'),
        );
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
        _showSnack(_tr(en: 'Group created', ar: 'تم إنشاء المجموعة'));
        if (context.mounted) {
          context.push('/chat/${result.value}');
        }
        return;
      }
      _showSnack(
        result.error?.message ??
            _tr(en: 'Failed to create group', ar: 'فشل إنشاء المجموعة'),
      );
    } finally {
      titleController.dispose();
      extraController.dispose();
    }
  }

  Future<void> _viewContactInfo() async {
    if (_isGroupConversation) {
      await _showGroupInfoSheet();
      return;
    }
    final profileUserId = await _resolveProfileUserIdForConversation();
    if (!mounted || profileUserId == null || profileUserId.isEmpty) {
      _showSnack(
        _tr(
          en: 'No participant info available',
          ar: 'لا توجد معلومات متاحة عن جهة الاتصال',
        ),
      );
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

  Future<void> _showGroupInfoSheet() async {
    final members = await _loadConversationMembers();
    final memberNames = await _resolveMemberDisplayNames(members);
    if (!mounted) {
      return;
    }

    final messages = _chatThreadCubit.state.messages;
    final mediaCount = messages
        .where(
          (m) => m.type == MessageType.image || m.type == MessageType.video,
        )
        .length;
    final docsCount = messages.where((m) => m.type == MessageType.file).length;
    final linksCount = _extractLinks(messages).length;
    final createdLabel = _conversationCreatedAt == null
        ? _tr(en: 'Unknown', ar: 'غير معروف')
        : _formatLastSeen(_conversationCreatedAt!);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                _tr(en: 'Group info', ar: 'معلومات المجموعة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _conversationTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  en: 'Created: $createdLabel',
                  ar: 'تاريخ الإنشاء: $createdLabel',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  en: '${members.length} members',
                  ar: '${members.length} أعضاء',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(_tr(en: 'Media', ar: 'الوسائط')),
                      trailing: Text('$mediaCount'),
                    ),
                    const Divider(height: 0),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(_tr(en: 'Documents', ar: 'المستندات')),
                      trailing: Text('$docsCount'),
                    ),
                    const Divider(height: 0),
                    ListTile(
                      leading: const Icon(Icons.link_outlined),
                      title: Text(_tr(en: 'Links', ar: 'الروابط')),
                      trailing: Text('$linksCount'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _tr(en: 'Participants', ar: 'المشاركون'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...members.map((memberId) {
                final displayName = memberNames[memberId] ?? memberId;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(displayName),
                  subtitle: displayName == memberId ? null : Text(memberId),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>> _resolveMemberDisplayNames(
    List<String> memberIds,
  ) async {
    final names = <String, String>{};
    final currentUserId = _resolveCurrentUserId();
    for (final memberId in memberIds) {
      if (memberId == currentUserId) {
        names[memberId] = _tr(en: 'You', ar: 'أنت');
      } else {
        names[memberId] = memberId;
      }
    }
    if (Firebase.apps.isEmpty || memberIds.isEmpty) {
      return names;
    }

    for (final memberId in memberIds) {
      if (memberId == currentUserId) {
        continue;
      }
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(FirebasePaths.users)
            .doc(memberId)
            .get();
        final data = snapshot.data() ?? const <String, dynamic>{};
        final displayName = (data['displayName'] as String?)?.trim();
        final phone = (data['phone'] as String?)?.trim();
        final value = (displayName != null && displayName.isNotEmpty)
            ? displayName
            : (phone != null && phone.isNotEmpty)
            ? phone
            : memberId;
        names[memberId] = value;
      } catch (_) {
        // Keep fallback member id on lookup errors.
      }
    }
    return names;
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
    final mediaItems = <_AttachmentItem>[];
    final docsItems = <_AttachmentItem>[];
    for (final message in messages) {
      if (message.isDeleted) {
        continue;
      }
      final isAttachmentMessage =
          message.type == MessageType.image ||
          message.type == MessageType.video ||
          message.type == MessageType.file;
      if (!isAttachmentMessage) {
        continue;
      }
      final payload = _tryDecodePayload(message.text);
      final source = _resolveAttachmentSource(
        payload,
        fallbackText: message.text,
      );
      if (source == null || source.isEmpty) {
        continue;
      }
      final title = payload?['name']?.toString().trim().isNotEmpty == true
          ? payload!['name']!.toString().trim()
          : _fallbackAttachmentTitle(message.type);
      final item = _AttachmentItem(
        title: title,
        source: source,
        messageType: message.type,
        meta: _messageMeta(message),
      );
      if (message.type == MessageType.file) {
        docsItems.add(item);
      } else {
        mediaItems.add(item);
      }
    }
    final links = _extractLinks(messages);

    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _tr(
                  en: 'Media (${mediaItems.length})',
                  ar: 'الوسائط (${mediaItems.length})',
                ),
              ),
            ),
            if (mediaItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _tr(en: 'No media found', ar: 'لا توجد وسائط'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...mediaItems.map(
                (item) => ListTile(
                  leading: Icon(
                    item.messageType == MessageType.image
                        ? Icons.image_outlined
                        : Icons.videocam_outlined,
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.meta),
                  onTap: () async {
                    if (item.messageType == MessageType.image) {
                      await _showImagePreview(item.source);
                      return;
                    }
                    await _openAttachmentUrl(item.source);
                  },
                ),
              ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                _tr(
                  en: 'Documents (${docsItems.length})',
                  ar: 'المستندات (${docsItems.length})',
                ),
              ),
            ),
            if (docsItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _tr(en: 'No documents found', ar: 'لا توجد مستندات'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...docsItems.map(
                (item) => ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(item.title),
                  subtitle: Text(item.meta),
                  onTap: () => _openAttachmentUrl(item.source),
                ),
              ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(
                _tr(
                  en: 'Links (${links.length})',
                  ar: 'الروابط (${links.length})',
                ),
              ),
            ),
            if (links.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _tr(en: 'No links found', ar: 'لا توجد روابط'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...links.map(
                (link) => ListTile(
                  title: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: _tr(en: 'Copy link', ar: 'نسخ الرابط'),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: link)),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                  onTap: () => _openAttachmentUrl(link),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _extractLinks(Iterable<ChatMessageView> messages) {
    final links = <String>{};
    final linkRegex = RegExp(r'https?://\S+');
    for (final message in messages) {
      for (final match in linkRegex.allMatches(message.text)) {
        final link = match.group(0);
        if (link != null && link.isNotEmpty) {
          links.add(link);
        }
      }
    }
    return links.toList(growable: false);
  }

  String _fallbackAttachmentTitle(MessageType type) {
    return switch (type) {
      MessageType.image => _tr(en: 'Image', ar: 'صورة'),
      MessageType.video => _tr(en: 'Video', ar: 'فيديو'),
      MessageType.file => _tr(en: 'Document', ar: 'مستند'),
      MessageType.voice => _tr(en: 'Voice note', ar: 'رسالة صوتية'),
      _ => type.name,
    };
  }

  String? _resolveAttachmentSource(
    Map<String, Object?>? payload, {
    String? fallbackText,
  }) {
    final nestedFile = payload?['file'];
    final nestedMedia = payload?['media'];
    final nestedMaps = <Map<dynamic, dynamic>>[
      if (nestedFile is Map) nestedFile,
      if (nestedMedia is Map) nestedMedia,
    ];
    final candidates = <Object?>[
      payload?['url'],
      payload?['downloadUrl'],
      payload?['fileUrl'],
      payload?['mediaUrl'],
      payload?['attachmentUrl'],
      payload?['audioUrl'],
      payload?['voiceUrl'],
      payload?['uri'],
      payload?['path'],
      payload?['filePath'],
      payload?['storagePath'],
      payload?['storageUri'],
      payload?['objectPath'],
      payload?['fullPath'],
      payload?['src'],
      payload?['source'],
      for (final item in nestedMaps) item['url'],
      for (final item in nestedMaps) item['downloadUrl'],
      for (final item in nestedMaps) item['fileUrl'],
      for (final item in nestedMaps) item['mediaUrl'],
      for (final item in nestedMaps) item['audioUrl'],
      for (final item in nestedMaps) item['voiceUrl'],
      for (final item in nestedMaps) item['path'],
      for (final item in nestedMaps) item['filePath'],
      for (final item in nestedMaps) item['storagePath'],
      for (final item in nestedMaps) item['objectPath'],
      for (final item in nestedMaps) item['src'],
      for (final item in nestedMaps) item['source'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          value != 'null' &&
          !value.startsWith('{') &&
          !value.startsWith('[')) {
        return value;
      }
    }
    final fallback = fallbackText?.trim();
    if (fallback != null &&
        fallback.isNotEmpty &&
        _seemsAttachmentText(fallback)) {
      return fallback;
    }
    return null;
  }

  bool _seemsAttachmentText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final lower = normalized.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('gs://')) {
      return true;
    }
    if (lower.startsWith('media/') ||
        lower.startsWith('status/') ||
        lower.startsWith('attachments/') ||
        lower.startsWith('upload/')) {
      return true;
    }
    return !normalized.contains(' ') &&
        (normalized.contains('/') || normalized.contains('\\'));
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
    if (downloadUrl == null || downloadUrl.isEmpty) {
      if (mounted) {
        _showSnack(
          _lastUploadFailureReason ?? 'Failed to upload ${type.name} file',
        );
      }
      return;
    }
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
      if (downloadUrl == null || downloadUrl.isEmpty) {
        _showSnack(_lastUploadFailureReason ?? 'Failed to upload voice note');
        return;
      }
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
    final source = _resolveAttachmentSource(
      payload,
      fallbackText: message.text,
    );
    if (source == null || source.isEmpty) {
      _showSnack(
        _tr(
          en: 'Voice note file is unavailable',
          ar: 'ملف الرسالة الصوتية غير متاح',
        ),
      );
      return false;
    }
    final url = await _resolveAttachmentDownloadUrl(source);
    if (url == null || url.isEmpty) {
      _showSnack(
        _tr(
          en: 'Voice note file is unavailable',
          ar: 'ملف الرسالة الصوتية غير متاح',
        ),
      );
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
      _showSnack(
        _tr(
          en: 'Failed to load this voice note',
          ar: 'فشل تحميل الرسالة الصوتية',
        ),
      );
      return false;
    }
  }

  Duration _resolveVoiceDuration(Map<String, Object?>? payload) {
    final durationValue = payload?['durationSec'] ?? payload?['duration'];
    final durationMsValue = payload?['durationMs'];
    if (durationValue is int && durationValue >= 0) {
      return Duration(seconds: durationValue);
    }
    if (durationValue is String) {
      final parsed = int.tryParse(durationValue);
      if (parsed != null && parsed >= 0) {
        return Duration(seconds: parsed);
      }
    }
    if (durationMsValue is int && durationMsValue >= 0) {
      return Duration(milliseconds: durationMsValue);
    }
    if (durationMsValue is String) {
      final parsed = int.tryParse(durationMsValue);
      if (parsed != null && parsed >= 0) {
        return Duration(milliseconds: parsed);
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
    _lastUploadFailureReason = null;
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
      final storagePath =
          'media/$uid/${widget.conversationId}/$timestamp-$safeName';
      final metadata = SettableMetadata(
        contentType: _contentTypeFor(type, file.extension),
      );
      return _uploadToStoragePath(
        storagePath: storagePath,
        metadata: metadata,
        bytes: bytes,
        filePath: filePath,
      );
    } catch (error) {
      _lastUploadFailureReason = 'Upload failed: $error';
      return null;
    }
  }

  Future<String?> _uploadFileFromPath({
    required String filePath,
    required String fileName,
    required String extension,
    required MessageType type,
  }) async {
    _lastUploadFailureReason = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return null;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storagePath =
          'media/$uid/${widget.conversationId}/$timestamp-$safeName';
      return _uploadToStoragePath(
        storagePath: storagePath,
        metadata: SettableMetadata(
          contentType: _contentTypeFor(type, extension),
        ),
        filePath: filePath,
      );
    } catch (error) {
      _lastUploadFailureReason = 'Upload failed: $error';
      return null;
    }
  }

  Future<String?> _uploadToStoragePath({
    required String storagePath,
    required SettableMetadata metadata,
    List<int>? bytes,
    String? filePath,
  }) async {
    String? supabaseFailureReason;
    if (_isSupabaseStorageConfigured) {
      final supabaseUrl = await _uploadToSupabasePath(
        storagePath: storagePath,
        contentType: metadata.contentType,
        bytes: bytes,
        filePath: filePath,
      );
      if (supabaseUrl != null && supabaseUrl.isNotEmpty) {
        return supabaseUrl;
      }
      supabaseFailureReason = _lastUploadFailureReason;
      if (!_enableFirebaseStorageUploadFallback) {
        return null;
      }
      AppLogger.warning(
        'Supabase upload failed. Falling back to Firebase Storage.',
        event: 'chat.media.upload.supabase_fallback',
        action: 'chat.media.upload',
        metadata: <String, Object?>{
          'path': storagePath,
          'reason': supabaseFailureReason,
        },
      );
    } else if (!_enableFirebaseStorageUploadFallback) {
      _lastUploadFailureReason =
          'Supabase is not configured for this run. Start with --dart-define-from-file=supabase.env.json';
      return null;
    }

    if (Firebase.apps.isEmpty) {
      _lastUploadFailureReason =
          supabaseFailureReason ?? 'No media storage provider is configured.';
      return null;
    }

    final storages = _storageCandidates();
    FirebaseException? lastFirebaseError;
    Object? lastError;
    for (final storage in storages) {
      final ref = storage.ref().child(storagePath);
      try {
        await _putObject(
          ref: ref,
          metadata: metadata,
          bytes: bytes,
          filePath: filePath,
        );
        return await ref.getDownloadURL();
      } catch (error, stackTrace) {
        AppLogger.warning(
          'Storage upload candidate failed (bucket=${storage.bucket}, path=$storagePath)',
          event: 'chat.media.upload.candidate_failed',
          action: 'chat.media.upload',
          metadata: <String, Object?>{
            'bucket': storage.bucket,
            'path': storagePath,
            'error': error.toString(),
          },
        );
        AppLogger.error(
          'Storage upload candidate error (bucket=${storage.bucket}, path=$storagePath)',
          error,
          stackTrace,
          event: 'chat.media.upload.candidate_exception',
          action: 'chat.media.upload',
          source: 'ChatPage',
          operation: 'uploadToStoragePath',
          metadata: <String, Object?>{
            'bucket': storage.bucket,
            'path': storagePath,
          },
        );
        lastError = error;
        if (error is FirebaseException) {
          lastFirebaseError = error;
        }
      }
    }
    if (lastFirebaseError?.code == 'object-not-found') {
      _lastUploadFailureReason =
          'Firebase Storage bucket is not initialized or not found for this project.';
    } else if (lastFirebaseError != null) {
      _lastUploadFailureReason =
          'Upload failed with Firebase error: ${lastFirebaseError.code}';
    } else if (lastError != null) {
      _lastUploadFailureReason = 'Upload failed: $lastError';
    }
    if (supabaseFailureReason != null && _lastUploadFailureReason != null) {
      _lastUploadFailureReason =
          '$supabaseFailureReason Firebase fallback failed: ${_lastUploadFailureReason!}';
    }
    return null;
  }

  bool get _isSupabaseStorageConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  SupabaseClient? _supabaseClientOrNull() {
    if (!_isSupabaseStorageConfigured) {
      return null;
    }
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _uploadToSupabasePath({
    required String storagePath,
    String? contentType,
    List<int>? bytes,
    String? filePath,
  }) async {
    final client = _supabaseClientOrNull();
    if (client == null) {
      _lastUploadFailureReason =
          'Supabase is configured but not initialized. Restart the app and try again.';
      return null;
    }

    final bucket = _supabaseStorageBucket.trim().isEmpty
        ? 'chat-media'
        : _supabaseStorageBucket.trim();
    final normalizedPath = storagePath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final storage = client.storage.from(bucket);

    try {
      if (bytes != null) {
        await _uploadSupabaseBinaryWithRetry(
          storage: storage,
          path: normalizedPath,
          bytes: Uint8List.fromList(bytes),
          contentType: contentType,
        );
      } else {
        if (filePath == null || filePath.isEmpty) {
          throw StateError('Missing attachment file path');
        }
        final file = File(filePath);
        final fileSize = await file.length();
        if (fileSize <= 25 * 1024 * 1024) {
          final data = await file.readAsBytes();
          await _uploadSupabaseBinaryWithRetry(
            storage: storage,
            path: normalizedPath,
            bytes: data,
            contentType: contentType,
          );
        } else {
          try {
            await _uploadSupabaseFileWithRetry(
              storage: storage,
              path: normalizedPath,
              file: file,
              contentType: contentType,
            );
          } catch (_) {
            if (fileSize > 40 * 1024 * 1024) {
              rethrow;
            }
            final fallbackBytes = await file.readAsBytes();
            await _uploadSupabaseBinaryWithRetry(
              storage: storage,
              path: normalizedPath,
              bytes: fallbackBytes,
              contentType: contentType,
            );
          }
        }
      }
      return storage.getPublicUrl(normalizedPath);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Supabase upload failed (bucket=$bucket, path=$normalizedPath)',
        event: 'chat.media.upload.supabase_failed',
        action: 'chat.media.upload',
        metadata: <String, Object?>{
          'bucket': bucket,
          'path': normalizedPath,
          'error': error.toString(),
        },
      );
      AppLogger.error(
        'Supabase upload exception (bucket=$bucket, path=$normalizedPath)',
        error,
        stackTrace,
        event: 'chat.media.upload.supabase_exception',
        action: 'chat.media.upload',
        source: 'ChatPage',
        operation: 'uploadToSupabasePath',
        metadata: <String, Object?>{'bucket': bucket, 'path': normalizedPath},
      );
      _lastUploadFailureReason = _supabaseUploadFailureReason(error);
      return null;
    }
  }

  Future<void> _uploadSupabaseBinaryWithRetry({
    required StorageFileApi storage,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    Object? lastError;
    final options = FileOptions(contentType: contentType, upsert: true);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await storage.uploadBinary(path, bytes, fileOptions: options);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Unable to upload attachment data');
  }

  Future<void> _uploadSupabaseFileWithRetry({
    required StorageFileApi storage,
    required String path,
    required File file,
    String? contentType,
  }) async {
    Object? lastError;
    final options = FileOptions(contentType: contentType, upsert: true);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await storage.upload(path, file, fileOptions: options);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 350 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Unable to upload attachment file');
  }

  String _supabaseUploadFailureReason(Object error) {
    final details = error.toString();
    final lower = details.toLowerCase();
    if (lower.contains('row-level security') ||
        lower.contains('row level security') ||
        lower.contains('violates row-level security')) {
      return 'Supabase policy blocked this upload. Allow insert on this bucket for your client role.';
    }
    if (lower.contains('bucket') && lower.contains('not found')) {
      return 'Supabase bucket is missing. Create bucket "$_supabaseStorageBucket" first.';
    }
    if (lower.contains('jwt') || lower.contains('token')) {
      return 'Supabase key is invalid or expired.';
    }
    return 'Supabase upload failed: $details';
  }

  List<FirebaseStorage> _storageCandidates() {
    if (Firebase.apps.isEmpty) {
      return <FirebaseStorage>[];
    }

    final options = Firebase.app().options;
    final configuredBucket = _normalizeBucketName(options.storageBucket);
    final projectId = options.projectId.trim();
    final preferredBuckets = <String>[];
    void addBucket(String? bucket) {
      final normalized = _normalizeBucketName(bucket);
      if (normalized == null || preferredBuckets.contains(normalized)) {
        return;
      }
      preferredBuckets.add(normalized);
    }

    // Prefer explicit appspot bucket when config provides firebasestorage.app,
    // then fallback to the configured bucket and project-derived aliases.
    if (configuredBucket != null &&
        configuredBucket.endsWith('.firebasestorage.app')) {
      addBucket(
        configuredBucket.replaceFirst('.firebasestorage.app', '.appspot.com'),
      );
      addBucket(configuredBucket);
    } else {
      addBucket(configuredBucket);
    }
    if (projectId.isNotEmpty) {
      addBucket('$projectId.appspot.com');
      addBucket('$projectId.firebasestorage.app');
    }

    final candidates = <FirebaseStorage>[];
    for (final bucket in preferredBuckets) {
      try {
        candidates.add(FirebaseStorage.instanceFor(bucket: 'gs://$bucket'));
      } catch (_) {
        // Ignore invalid candidate buckets.
      }
    }
    candidates.add(FirebaseStorage.instance);
    return candidates;
  }

  String? _normalizeBucketName(String? bucket) {
    final trimmed = bucket?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    var normalized = trimmed;
    if (normalized.startsWith('gs://')) {
      normalized = normalized.substring(5);
    }
    final slashIndex = normalized.indexOf('/');
    if (slashIndex >= 0) {
      normalized = normalized.substring(0, slashIndex);
    }
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _putObject({
    required Reference ref,
    required SettableMetadata metadata,
    List<int>? bytes,
    String? filePath,
  }) async {
    if (bytes != null) {
      await _putDataWithRetry(
        ref: ref,
        metadata: metadata,
        bytes: Uint8List.fromList(bytes),
      );
      return;
    }

    if (filePath == null || filePath.isEmpty) {
      throw StateError('Missing attachment file path');
    }

    final file = File(filePath);
    final fileSize = await file.length();
    // Small files are uploaded using putData to avoid flaky resumable sessions
    // on some Android devices.
    if (fileSize <= 25 * 1024 * 1024) {
      final data = await file.readAsBytes();
      await _putDataWithRetry(ref: ref, metadata: metadata, bytes: data);
      return;
    }

    try {
      await _putFileWithRetry(ref: ref, metadata: metadata, file: file);
    } catch (_) {
      // Last fallback for large files when resumable sessions fail repeatedly.
      if (fileSize > 40 * 1024 * 1024) {
        rethrow;
      }
      final fallbackBytes = await file.readAsBytes();
      await _putDataWithRetry(
        ref: ref,
        metadata: metadata,
        bytes: fallbackBytes,
      );
    }
  }

  Future<void> _putDataWithRetry({
    required Reference ref,
    required SettableMetadata metadata,
    required Uint8List bytes,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await ref.putData(bytes, metadata);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Unable to upload attachment data');
  }

  Future<void> _putFileWithRetry({
    required Reference ref,
    required SettableMetadata metadata,
    required File file,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await ref.putFile(file, metadata);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 350 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Unable to upload attachment file');
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
        if (extension?.toLowerCase() == 'm4a') {
          return 'audio/mp4';
        }
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (!message.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.reply_outlined),
                    title: Text(_tr(en: 'Reply', ar: 'رد')),
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.reply),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: Text(_tr(en: 'Copy', ar: 'نسخ')),
                    onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.forward_outlined),
                    title: Text(_tr(en: 'Forward', ar: 'إعادة توجيه')),
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.forward),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.emoji_emotions_outlined),
                    title: Text(_tr(en: 'React', ar: 'تفاعل')),
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.react),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: Icon(
                      message.isStarred ? Icons.star : Icons.star_outline,
                    ),
                    title: Text(
                      message.isStarred
                          ? _tr(
                              en: 'Remove from starred',
                              ar: 'إزالة من الرسائل المميزة',
                            )
                          : _tr(
                              en: 'Add to starred',
                              ar: 'إضافة إلى الرسائل المميزة',
                            ),
                    ),
                    onTap: () => Navigator.of(context).pop(_MessageAction.star),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: Icon(
                      message.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(
                      message.isPinned
                          ? _tr(en: 'Unpin message', ar: 'إلغاء تثبيت الرسالة')
                          : _tr(en: 'Pin message', ar: 'تثبيت الرسالة'),
                    ),
                    onTap: () => Navigator.of(context).pop(_MessageAction.pin),
                  ),
                if (message.isMine)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(_localizedInfoLabel()),
                    onTap: () => Navigator.of(context).pop(_MessageAction.info),
                  ),
                if (message.isMine &&
                    !message.isDeleted &&
                    (message.type == MessageType.text ||
                        message.type == MessageType.system))
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(_tr(en: 'Edit', ar: 'تعديل')),
                    onTap: () => Navigator.of(context).pop(_MessageAction.edit),
                  ),
                if (!message.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(_tr(en: 'Delete', ar: 'حذف')),
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.delete),
                  ),
              ],
            ),
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
          _showSnack(_tr(en: 'Message copied', ar: 'تم نسخ الرسالة'));
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
              title: Text(_tr(en: 'Remove my reaction', ar: 'إزالة تفاعلي')),
              onTap: () => Navigator.of(context).pop(''),
            ),
            _buildReactionOption(context, '\u{1F44D}'),
            _buildReactionOption(context, '\u2764\uFE0F'),
            _buildReactionOption(context, '\u{1F602}'),
            _buildReactionOption(context, '\u{1F62E}'),
            _buildReactionOption(context, '\u{1F622}'),
            _buildReactionOption(context, '\u{1F64F}'),
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
      _showSnack(
        selected.isEmpty
            ? _tr(en: 'Reaction removed', ar: 'تمت إزالة التفاعل')
            : _tr(en: 'Reaction updated', ar: 'تم تحديث التفاعل'),
      );
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
            ? _tr(
                en: 'Removed from starred messages',
                ar: 'تمت الإزالة من الرسائل المميزة',
              )
            : _tr(
                en: 'Added to starred messages',
                ar: 'تمت الإضافة إلى الرسائل المميزة',
              ),
      );
    }
  }

  Future<void> _togglePinMessage(ChatMessageView message) async {
    final success = await _chatThreadCubit.toggleMessagePin(message);
    if (success && mounted) {
      _showSnack(
        message.isPinned
            ? _tr(en: 'Message unpinned', ar: 'تم إلغاء تثبيت الرسالة')
            : _tr(en: 'Message pinned', ar: 'تم تثبيت الرسالة'),
      );
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
      _showSnack(_tr(en: 'Message updated', ar: 'تم تحديث الرسالة'));
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
      _showSnack(_tr(en: 'Message forwarded', ar: 'تمت إعادة توجيه الرسالة'));
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
        ? _tr(en: 'Message deleted for you', ar: 'تم حذف الرسالة لديك')
        : _tr(en: 'Message deleted for everyone', ar: 'تم حذف الرسالة للجميع');
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
              title: Text(_tr(en: 'Delete for me', ar: 'حذف لدي')),
              onTap: () => Navigator.of(context).pop(_DeleteScope.forMe),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(_tr(en: 'Delete for everyone', ar: 'حذف لدى الجميع')),
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
                title: Text(_conversationLabel(conversation)),
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
    if (!message.isMine) {
      _showSnack(
        _tr(
          en: 'Message info is available only for sender',
          ar: 'معلومات الرسالة متاحة للمرسل فقط',
        ),
      );
      return;
    }
    final sentAt = message.sentAt.toString();
    final editedAt = message.editedAt?.toString() ?? '-';
    final deletedAt = message.deletedForAllAt?.toString() ?? '-';
    final reactions = message.reactionsByUser.values.isEmpty
        ? '-'
        : message.reactionsByUser.values.join(' ');
    final details = _tr(
      en:
          'Message ID: ${message.id}\n'
          'Sender ID: ${message.senderId}\n'
          'Sent at: $sentAt\n'
          'Edited at: $editedAt\n'
          'Deleted at: $deletedAt\n'
          'Reply to: ${message.replyToMessageId ?? '-'}\n'
          'Starred: ${message.isStarred}\n'
          'Pinned: ${message.isPinned}\n'
          'Reactions: $reactions',
      ar:
          'معرف الرسالة: ${message.id}\n'
          'معرف المرسل: ${message.senderId}\n'
          'وقت الإرسال: $sentAt\n'
          'وقت التعديل: $editedAt\n'
          'وقت الحذف: $deletedAt\n'
          'رد على: ${message.replyToMessageId ?? '-'}\n'
          'مميزة: ${message.isStarred ? 'نعم' : 'لا'}\n'
          'مثبتة: ${message.isPinned ? 'نعم' : 'لا'}\n'
          'التفاعلات: $reactions',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr(en: 'Message info', ar: 'معلومات الرسالة')),
        content: SelectableText(details),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_tr(en: 'Close', ar: 'إغلاق')),
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
        final title = payload?['name']?.toString().trim().isNotEmpty == true
            ? payload!['name']!.toString().trim()
            : _fallbackAttachmentTitle(message.type);
        final attachmentSource = _resolveAttachmentSource(
          payload,
          fallbackText: message.text,
        );
        final hasAttachment =
            attachmentSource != null && attachmentSource.isNotEmpty;
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
            if (message.type == MessageType.image && hasAttachment)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildImageAttachmentPreview(attachmentSource),
              )
            else if (hasAttachment)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openAttachmentUrl(attachmentSource),
                      icon: Icon(
                        message.type == MessageType.file
                            ? Icons.description_outlined
                            : Icons.play_circle_outline,
                      ),
                      label: Text(
                        message.type == MessageType.file
                            ? _tr(en: 'Open document', ar: 'فتح المستند')
                            : _tr(en: 'Open video', ar: 'فتح الفيديو'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: attachmentSource),
                      ),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(_tr(en: 'Copy link', ar: 'نسخ الرابط')),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildAttachmentErrorTile(
                  icon: Icons.cloud_off_outlined,
                  message: _tr(
                    en: 'Attachment link is unavailable',
                    ar: 'رابط الملف غير متاح',
                  ),
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
          return Text(
            _tr(en: 'Location: $lat, $lng', ar: 'الموقع: $lat, $lng'),
          );
        }
        if (name != null && phone != null) {
          return Text(
            _tr(
              en: 'Contact: $name ($phone)',
              ar: 'جهة الاتصال: $name ($phone)',
            ),
          );
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

  Widget _buildImageAttachmentPreview(String source) {
    return FutureBuilder<String?>(
      future: _resolveAttachmentDownloadUrl(source),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: 220,
            height: 140,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }
        final resolvedUrl = snapshot.data;
        if (resolvedUrl == null || resolvedUrl.isEmpty) {
          return _buildAttachmentErrorTile(
            icon: Icons.broken_image_outlined,
            message: _tr(
              en: 'Image preview is unavailable',
              ar: 'معاينة الصورة غير متاحة',
            ),
          );
        }
        return GestureDetector(
          onTap: () => _showImagePreview(source),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              resolvedUrl,
              width: 220,
              height: 140,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildAttachmentErrorTile(
                  icon: Icons.broken_image_outlined,
                  message: _tr(
                    en: 'Image preview is unavailable',
                    ar: 'معاينة الصورة غير متاحة',
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAttachmentUrl(String source) async {
    final resolvedUrl = await _resolveAttachmentDownloadUrl(source);
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      _showSnack(
        _tr(en: 'Attachment link is invalid', ar: 'رابط الملف غير صالح'),
      );
      return;
    }
    final uri = Uri.tryParse(resolvedUrl.trim());
    if (uri == null || !uri.hasScheme) {
      _showSnack(
        _tr(en: 'Attachment link is invalid', ar: 'رابط الملف غير صالح'),
      );
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showSnack(_tr(en: 'Unable to open attachment', ar: 'تعذر فتح الملف'));
      }
    } catch (_) {
      _showSnack(_tr(en: 'Unable to open attachment', ar: 'تعذر فتح الملف'));
    }
  }

  Future<void> _showImagePreview(String source) async {
    final resolvedUrl = await _resolveAttachmentDownloadUrl(source);
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      _showSnack(
        _tr(en: 'Image preview is unavailable', ar: 'معاينة الصورة غير متاحة'),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            resolvedUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildAttachmentErrorTile(
                icon: Icons.broken_image_outlined,
                message: _tr(
                  en: 'Image preview is unavailable',
                  ar: 'معاينة الصورة غير متاحة',
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<String?> _resolveAttachmentDownloadUrl(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      return Future<String?>.value(null);
    }
    return _resolvedAttachmentUrlCache.putIfAbsent(
      normalized,
      () => _resolveAttachmentDownloadUrlInternal(normalized),
    );
  }

  Future<String?> _resolveAttachmentDownloadUrlInternal(String source) async {
    final uri = Uri.tryParse(source);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority) {
      return source;
    }

    if (uri != null && uri.scheme == 'gs') {
      final direct = await _resolveGsDownloadUrl(source);
      if (direct != null) {
        return direct;
      }
    }

    final normalizedPath = source.replaceAll('\\', '/').replaceFirst('/', '');
    if (normalizedPath.isNotEmpty) {
      for (final storage in _storageCandidates()) {
        try {
          return await storage.ref().child(normalizedPath).getDownloadURL();
        } catch (_) {
          // Try the next configured bucket.
        }
      }
    }

    return null;
  }

  Future<String?> _resolveGsDownloadUrl(String source) async {
    try {
      return await FirebaseStorage.instance.refFromURL(source).getDownloadURL();
    } catch (_) {
      final swapped = _swapBucketSuffix(source);
      if (swapped == null) {
        return null;
      }
      try {
        return await FirebaseStorage.instance
            .refFromURL(swapped)
            .getDownloadURL();
      } catch (_) {
        return null;
      }
    }
  }

  String? _swapBucketSuffix(String gsUrl) {
    final uri = Uri.tryParse(gsUrl);
    if (uri == null || uri.scheme != 'gs' || uri.host.isEmpty) {
      return null;
    }
    final bucket = uri.host;
    if (bucket.endsWith('.firebasestorage.app')) {
      final swappedBucket = bucket.replaceFirst(
        '.firebasestorage.app',
        '.appspot.com',
      );
      return 'gs://$swappedBucket${uri.path}';
    }
    if (bucket.endsWith('.appspot.com')) {
      final swappedBucket = bucket.replaceFirst(
        '.appspot.com',
        '.firebasestorage.app',
      );
      return 'gs://$swappedBucket${uri.path}';
    }
    return null;
  }

  Widget _buildAttachmentErrorTile({
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceNoteBody(
    ChatMessageView message,
    Map<String, Object?>? payload,
  ) {
    final source = _resolveAttachmentSource(
      payload,
      fallbackText: message.text,
    );
    final hasUrl = source != null && source.isNotEmpty;
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
                tooltip: isActive && _isVoicePlaying
                    ? _tr(en: 'Pause', ar: 'إيقاف مؤقت')
                    : _tr(en: 'Play', ar: 'تشغيل'),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(_tr(en: 'Voice note', ar: 'رسالة صوتية')),
              ),
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
                _tr(
                  en: 'Audio file is unavailable in this environment',
                  ar: 'ملف الصوت غير متاح في هذه البيئة',
                ),
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

  String _defaultConversationTitle() {
    return _tr(
      en: 'Conversation ${_shortId(widget.conversationId)}',
      ar: 'محادثة ${_shortId(widget.conversationId)}',
    );
  }

  String _bootstrapConversationTitle() {
    return 'Conversation ${_shortId(widget.conversationId)}';
  }

  String _conversationLabel(Conversation conversation) {
    final title = conversation.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return conversation.type == ConversationType.group
        ? _tr(
            en: 'Group ${_shortId(conversation.id)}',
            ar: 'مجموعة ${_shortId(conversation.id)}',
          )
        : _tr(
            en: 'Direct chat ${_shortId(conversation.id)}',
            ar: 'دردشة مباشرة ${_shortId(conversation.id)}',
          );
  }

  bool _isArabicUi() {
    return Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('ar');
  }

  String _localizedInfoLabel() {
    return _tr(en: 'Info', ar: 'معلومات الرسالة');
  }

  String _tr({required String en, required String ar}) {
    return _isArabicUi() ? ar : en;
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

class _AttachmentItem {
  const _AttachmentItem({
    required this.title,
    required this.source,
    required this.messageType,
    required this.meta,
  });

  final String title;
  final String source;
  final MessageType messageType;
  final String meta;
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
  exportDebugLogs,
}

enum _AttachmentAction { image, video, file, location, contact }
