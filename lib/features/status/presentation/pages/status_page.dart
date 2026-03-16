import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/bottom_nav_visibility.dart';
import 'package:chatify/core/common/floating_nav_metrics.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:chatify/features/status/domain/usecases/create_status_use_case.dart';
import 'package:chatify/features/status/presentation/bloc/status_cubit.dart';
import 'package:chatify/features/status/presentation/models/status_payload.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

const Duration _maxStatusVideoDuration = Duration(minutes: 1);
const List<String> _imageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
];
const List<String> _videoExtensions = <String>[
  'mp4',
  'mov',
  'm4v',
  'mkv',
  'webm',
];
const List<String> _audioExtensions = <String>[
  'mp3',
  'aac',
  'm4a',
  'wav',
  'ogg',
];
const List<Color> _statusBackgroundPalette = <Color>[
  Color(0xFFEEF2FA),
  Color(0xFFFFF3E0),
  Color(0xFFE3F2FD),
  Color(0xFFE8F5E9),
  Color(0xFFF3E5F5),
  Color(0xFFFFEBEE),
  Color(0xFF263238),
];
const List<Color> _statusTextPalette = <Color>[
  Color(0xFF1B2D41),
  Color(0xFF0F172A),
  Color(0xFFFFFFFF),
  Color(0xFFFFF8E1),
  Color(0xFF0B3954),
];

final Map<String, Future<String>> _authorLabelCache =
    <String, Future<String>>{};

Future<String> _resolveAuthorLabel(String authorId) {
  final trimmed = authorId.trim();
  if (trimmed.isEmpty) {
    return Future.value('Unknown');
  }
  return _authorLabelCache.putIfAbsent(trimmed, () async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && currentUserId == trimmed) {
      return 'You';
    }
    if (Firebase.apps.isEmpty) {
      return trimmed;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirebasePaths.users)
          .doc(trimmed)
          .get();
      if (!snapshot.exists) {
        return trimmed;
      }
      final data = snapshot.data();
      final displayName = data?['displayName']?.toString().trim();
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
      final phone = data?['phone']?.toString().trim();
      if (phone != null && phone.isNotEmpty) {
        return phone;
      }
    } catch (_) {
      return trimmed;
    }
    return trimmed;
  });
}

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final List<_LocalStatusEntry> _localEntries = [
    _LocalStatusEntry(
      id: 'local-1',
      author: 'Alice',
      payload: 'Sprint update ready',
    ),
  ];

  bool get _hasActiveFirebaseUser =>
      Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null;

  bool get _hasWiredStatus =>
      getIt.isRegistered<StatusCubit>() &&
      getIt.isRegistered<CreateStatusUseCase>() &&
      _hasActiveFirebaseUser;

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredStatus) {
      return _buildFilteredScaffold(
        entries: _localEntries,
        loading: false,
        showDemoHint: true,
        currentUserId: _resolveAuthorId(),
        onAddStatus: _createLocalStatus,
      );
    }

    return BlocProvider(
      create: (_) => getIt<StatusCubit>(),
      child: BlocConsumer<StatusCubit, StatusState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage &&
            current.errorMessage != null,
        listener: (context, state) {
          final message = state.errorMessage;
          if (message == null || !mounted) {
            return;
          }
          _showSnack(message);
          context.read<StatusCubit>().clearError();
        },
        builder: (context, state) {
          final entries = state.items
              .map(
                (item) => _LocalStatusEntry(
                  id: item.id,
                  author: item.authorId,
                  payload: item.ciphertextRef,
                  createdAt: item.createdAt,
                ),
              )
              .toList();
          return _buildFilteredScaffold(
            entries: entries,
            loading: state.loading,
            showDemoHint: entries.isEmpty && !state.loading,
            currentUserId: FirebaseAuth.instance.currentUser?.uid,
            onAddStatus: _createWiredStatus,
          );
        },
      ),
    );
  }

  Widget _buildFilteredScaffold({
    required List<_LocalStatusEntry> entries,
    required bool loading,
    required bool showDemoHint,
    required String? currentUserId,
    required Future<void> Function() onAddStatus,
  }) {
    final uid = currentUserId?.trim();
    if (uid == null || uid.isEmpty || Firebase.apps.isEmpty) {
      return _StatusScaffold(
        entries: entries,
        loading: loading,
        showDemoHint: showDemoHint,
        currentUserId: uid,
        onAddStatus: onAddStatus,
        onOpenStatus: _openStatusViewer,
        allowedViewerIds: null,
        onOpenMyStatuses: (entries, allowedViewerIds) => _openMyStatuses(
          entries: entries,
          allowedViewerIds: allowedViewerIds,
          onAddStatus: onAddStatus,
        ),
      );
    }
    return StreamBuilder<Set<String>>(
      stream: _watchAllowedAuthors(uid),
      builder: (context, snapshot) {
        final allowed = snapshot.data ?? <String>{uid};
        final filtered = entries
            .where((entry) => allowed.contains(entry.author.trim()))
            .toList(growable: false);
        return _StatusScaffold(
          entries: filtered,
          loading: loading,
          showDemoHint: showDemoHint,
          currentUserId: uid,
          onAddStatus: onAddStatus,
          onOpenStatus: _openStatusViewer,
          allowedViewerIds: allowed,
          onOpenMyStatuses: (entries, allowedViewerIds) => _openMyStatuses(
            entries: entries,
            allowedViewerIds: allowedViewerIds,
            onAddStatus: onAddStatus,
          ),
        );
      },
    );
  }

  Stream<Set<String>> _watchAllowedAuthors(String uid) {
    return FirebaseFirestore.instance
        .collection(FirebasePaths.conversations)
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final allowed = <String>{uid};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final members = data['memberIds'];
            if (members is! List) {
              continue;
            }
            for (final raw in members) {
              final memberId = raw?.toString().trim() ?? '';
              if (memberId.isNotEmpty) {
                allowed.add(memberId);
              }
            }
          }
          return allowed;
        });
  }

  Future<void> _createWiredStatus() async {
    final draft = await _composeStatus();
    if (!mounted || draft == null) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _showSnack('Sign in first before posting status');
      return;
    }

    try {
      final useCase = getIt<CreateStatusUseCase>();
      final result = await useCase(
        CreateStatusParams(
          authorId: uid,
          mediaType: draft.mediaType,
          ciphertextRef: draft.payload.toJsonString(),
        ),
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        _showSnack('Status published');
        return;
      }
      _showSnack(result.error?.message ?? 'Could not publish status');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Could not publish status: $error');
    }
  }

  Future<void> _createLocalStatus() async {
    try {
      final draft = await _composeStatus();
      if (!mounted || draft == null) {
        return;
      }
      setState(() {
        _localEntries.insert(
          0,
          _LocalStatusEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            author: _resolveAuthorId(),
            payload: draft.payload.toJsonString(),
            createdAt: DateTime.now(),
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Could not create status: $error');
    }
  }

  Future<_StatusDraft?> _composeStatus() async {
    final choice = await showModalBottomSheet<_StatusComposerChoice>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Text status'),
                onTap: () =>
                    Navigator.of(context).pop(_StatusComposerChoice.text),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Photo status'),
                onTap: () =>
                    Navigator.of(context).pop(_StatusComposerChoice.image),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video status'),
                onTap: () =>
                    Navigator.of(context).pop(_StatusComposerChoice.video),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return null;
    }

    switch (choice) {
      case _StatusComposerChoice.text:
        return _composeTextStatus();
      case _StatusComposerChoice.image:
        return _composeMediaStatus(StatusPayloadType.image);
      case _StatusComposerChoice.video:
        return _composeMediaStatus(StatusPayloadType.video);
    }
  }

  Future<_StatusDraft?> _composeTextStatus() async {
    final input = await showDialog<_TextStatusInput>(
      context: context,
      builder: (context) => const _TextStatusDialog(),
    );
    if (!mounted || input == null) {
      return null;
    }
    final text = input.text.trim();
    if (text.isEmpty) {
      _showSnack('Status text is required');
      return null;
    }

    String? musicUrl;
    if (input.musicFile != null) {
      final uploaded = await _runWithLoader<String?>(
        task: () => _uploadStatusFile(
          file: input.musicFile!,
          folder: 'music',
          contentType: _contentTypeForAudio(input.musicFile!.extension),
        ),
        label: 'Uploading music...',
      );
      if (!mounted) {
        return null;
      }
      if (uploaded == null || uploaded.isEmpty) {
        _showSnack('Failed to upload music');
        return null;
      }
      musicUrl = uploaded;
    }

    final payload = StatusPayload(
      type: StatusPayloadType.text,
      text: text,
      backgroundColor: input.backgroundColor,
      textColor: input.textColor,
      musicUrl: musicUrl,
      musicDurationSeconds:
          musicUrl == null ? null : StatusPayloadDefaults.musicDurationSeconds,
    );
    return _StatusDraft(payload: payload, mediaType: StatusPayloadType.text.name);
  }

  Future<_StatusDraft?> _composeMediaStatus(StatusPayloadType type) async {
    if (Firebase.apps.isEmpty) {
      _showSnack('Firebase is not configured for media uploads');
      return null;
    }
    if (FirebaseAuth.instance.currentUser?.uid == null) {
      _showSnack('Sign in first before uploading media');
      return null;
    }

    final mediaFile = await _pickMediaFile(type);
    if (!mounted || mediaFile == null) {
      return null;
    }

    if (type == StatusPayloadType.video) {
      final ok = await _validateVideoDuration(mediaFile);
      if (!mounted || !ok) {
        return null;
      }
    }

    final input = await showDialog<_MediaStatusInput>(
      context: context,
      builder: (context) => _MediaStatusDialog(
        allowMusic: type == StatusPayloadType.image,
      ),
    );
    if (!mounted || input == null) {
      return null;
    }

    final draft = await _runWithLoader<_StatusDraft?>(
      task: () async {
        final mediaUrl = await _uploadStatusFile(
          file: mediaFile,
          folder: type == StatusPayloadType.image ? 'images' : 'videos',
          contentType: _contentTypeForMedia(type, mediaFile.extension),
        );
        if (mediaUrl == null || mediaUrl.isEmpty) {
          return null;
        }

        String? musicUrl;
        if (input.musicFile != null) {
          final uploadedMusic = await _uploadStatusFile(
            file: input.musicFile!,
            folder: 'music',
            contentType: _contentTypeForAudio(input.musicFile!.extension),
          );
          if (uploadedMusic == null || uploadedMusic.isEmpty) {
            return null;
          }
          musicUrl = uploadedMusic;
        }

        final payload = StatusPayload(
          type: type,
          mediaUrl: mediaUrl,
          caption: input.caption?.trim(),
          musicUrl: musicUrl,
          musicDurationSeconds: musicUrl == null
              ? null
              : StatusPayloadDefaults.musicDurationSeconds,
        );
        return _StatusDraft(payload: payload, mediaType: type.name);
      },
      label: 'Uploading status...',
    );

    if (!mounted) {
      return null;
    }
    if (draft == null) {
      _showSnack('Could not upload status');
      return null;
    }
    return draft;
  }

  Future<T?> _runWithLoader<T>({
    required Future<T?> Function() task,
    required String label,
  }) async {
    if (!mounted) {
      return null;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
    try {
      return await task();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<PlatformFile?> _pickMediaFile(StatusPayloadType type) async {
    final extensions =
        type == StatusPayloadType.image ? _imageExtensions : _videoExtensions;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: kIsWeb,
    );
    return result?.files.single;
  }

  Future<bool> _validateVideoDuration(PlatformFile file) async {
    if (kIsWeb) {
      return true;
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      return true;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration > _maxStatusVideoDuration) {
        _showSnack('Video must be 60 seconds or less');
        return false;
      }
    } catch (_) {
      return true;
    } finally {
      await controller.dispose();
    }
    return true;
  }

  String _contentTypeForMedia(StatusPayloadType type, String? extension) {
    final normalized = extension?.toLowerCase().replaceAll('.', '') ?? '';
    if (type == StatusPayloadType.video) {
      if (normalized == 'mov') {
        return 'video/quicktime';
      }
      if (normalized == 'webm') {
        return 'video/webm';
      }
      return 'video/mp4';
    }
    if (normalized == 'png') {
      return 'image/png';
    }
    if (normalized == 'gif') {
      return 'image/gif';
    }
    if (normalized == 'webp') {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String _contentTypeForAudio(String? extension) {
    final normalized = extension?.toLowerCase().replaceAll('.', '') ?? '';
    if (normalized == 'wav') {
      return 'audio/wav';
    }
    if (normalized == 'ogg') {
      return 'audio/ogg';
    }
    if (normalized == 'aac') {
      return 'audio/aac';
    }
    if (normalized == 'm4a') {
      return 'audio/mp4';
    }
    return 'audio/mpeg';
  }

  Future<String?> _uploadStatusFile({
    required PlatformFile file,
    required String folder,
    required String contentType,
  }) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final bytes = file.bytes;
    final path = file.path;
    if (bytes == null && (path == null || path.isEmpty)) {
      return null;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final storagePath = 'status/$uid/$folder/$timestamp-$safeName';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final metadata = SettableMetadata(contentType: contentType);
    try {
      if (bytes != null) {
        await ref.putData(Uint8List.fromList(bytes), metadata);
      } else {
        await ref.putFile(File(path!), metadata);
      }
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  String _resolveAuthorId() {
    if (!getIt.isRegistered<FirebaseAuth>()) {
      return 'local-debug-user';
    }
    return getIt<FirebaseAuth>().currentUser?.uid ?? 'local-debug-user';
  }

  void _openStatusViewer(_StatusEntryView entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _StatusViewer(entry: entry),
      ),
    );
  }

  void _openMyStatuses({
    required List<_StatusEntryView> entries,
    required Set<String>? allowedViewerIds,
    required Future<void> Function() onAddStatus,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MyStatusListPage(
          entries: entries,
          allowedViewerIds: allowedViewerIds,
          onOpenStatus: _openStatusViewer,
          onAddStatus: onAddStatus,
          onEditStatus: _editStatusEntry,
          onDeleteStatus: _deleteStatusEntry,
        ),
      ),
    );
  }

  Future<StatusPayload?> _editStatusEntry(_StatusEntryView entry) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        currentUserId != entry.entry.author) {
      _showSnack('You can only edit your own status');
      return null;
    }
    final payload = entry.payload;
    switch (payload.type) {
      case StatusPayloadType.text:
        return _editTextStatus(entry, payload);
      case StatusPayloadType.image:
        return _editMediaStatus(
          entry,
          payload,
          allowMusic: true,
        );
      case StatusPayloadType.video:
        return _editMediaStatus(
          entry,
          payload,
          allowMusic: false,
        );
    }
  }

  Future<StatusPayload?> _editTextStatus(
    _StatusEntryView entry,
    StatusPayload payload,
  ) async {
    final input = await showDialog<_TextStatusInput>(
      context: context,
      builder: (context) => _TextStatusDialog(
        initialText: payload.text,
        initialBackgroundColor:
            payload.backgroundColor ?? StatusPayloadDefaults.backgroundColor,
        initialTextColor: payload.textColor ?? StatusPayloadDefaults.textColor,
        existingMusicUrl: payload.musicUrl,
      ),
    );
    if (!mounted || input == null) {
      return null;
    }

    var musicUrl = payload.musicUrl;
    if (input.removeExistingMusic) {
      musicUrl = null;
    }
    if (input.musicFile != null) {
      final uploaded = await _runWithLoader<String?>(
        task: () => _uploadStatusFile(
          file: input.musicFile!,
          folder: 'music',
          contentType: _contentTypeForAudio(input.musicFile!.extension),
        ),
        label: 'Updating music...',
      );
      if (!mounted) {
        return null;
      }
      if (uploaded == null || uploaded.isEmpty) {
        _showSnack('Failed to upload music');
        return null;
      }
      musicUrl = uploaded;
    }

    final updated = StatusPayload(
      type: StatusPayloadType.text,
      text: input.text.trim(),
      backgroundColor: input.backgroundColor,
      textColor: input.textColor,
      musicUrl: musicUrl,
      musicDurationSeconds:
          musicUrl == null ? null : StatusPayloadDefaults.musicDurationSeconds,
    );
    final success = await _persistStatusUpdate(entry, updated);
    return success ? updated : null;
  }

  Future<StatusPayload?> _editMediaStatus(
    _StatusEntryView entry,
    StatusPayload payload, {
    required bool allowMusic,
  }) async {
    final input = await showDialog<_MediaStatusInput>(
      context: context,
      builder: (context) => _MediaStatusDialog(
        allowMusic: allowMusic,
        initialCaption: payload.caption,
        existingMusicUrl: allowMusic ? payload.musicUrl : null,
      ),
    );
    if (!mounted || input == null) {
      return null;
    }

    var musicUrl = allowMusic ? payload.musicUrl : null;
    if (allowMusic && input.removeExistingMusic) {
      musicUrl = null;
    }
    if (allowMusic && input.musicFile != null) {
      final uploaded = await _runWithLoader<String?>(
        task: () => _uploadStatusFile(
          file: input.musicFile!,
          folder: 'music',
          contentType: _contentTypeForAudio(input.musicFile!.extension),
        ),
        label: 'Updating music...',
      );
      if (!mounted) {
        return null;
      }
      if (uploaded == null || uploaded.isEmpty) {
        _showSnack('Failed to upload music');
        return null;
      }
      musicUrl = uploaded;
    }

    final updated = StatusPayload(
      type: payload.type,
      mediaUrl: payload.mediaUrl,
      caption: input.caption?.trim(),
      musicUrl: musicUrl,
      musicDurationSeconds:
          musicUrl == null ? null : StatusPayloadDefaults.musicDurationSeconds,
    );
    final success = await _persistStatusUpdate(entry, updated);
    return success ? updated : null;
  }

  Future<bool> _persistStatusUpdate(
    _StatusEntryView entry,
    StatusPayload payload,
  ) async {
    if (Firebase.apps.isEmpty) {
      _showSnack('Firebase is not configured');
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || uid != entry.entry.author) {
      _showSnack('You can only edit your own status');
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.status)
          .doc(uid)
          .collection(FirebasePaths.items)
          .doc(entry.entry.id)
          .set({
            'mediaType': payload.type.name,
            'ciphertextRef': payload.toJsonString(),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
      _showSnack('Status updated');
      return true;
    } catch (error) {
      _showSnack('Could not update status: $error');
      return false;
    }
  }

  Future<bool> _deleteStatusEntry(_StatusEntryView entry) async {
    if (Firebase.apps.isEmpty) {
      _showSnack('Firebase is not configured');
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || uid != entry.entry.author) {
      _showSnack('You can only delete your own status');
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.status)
          .doc(uid)
          .collection(FirebasePaths.items)
          .doc(entry.entry.id)
          .delete();
      _showSnack('Status deleted');
      return true;
    } catch (error) {
      _showSnack('Could not delete status: $error');
      return false;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.entries,
    required this.loading,
    required this.showDemoHint,
    required this.currentUserId,
    required this.onAddStatus,
    required this.onOpenStatus,
    required this.allowedViewerIds,
    required this.onOpenMyStatuses,
  });

  final List<_LocalStatusEntry> entries;
  final bool loading;
  final bool showDemoHint;
  final String? currentUserId;
  final Future<void> Function() onAddStatus;
  final void Function(_StatusEntryView entry) onOpenStatus;
  final Set<String>? allowedViewerIds;
  final void Function(
    List<_StatusEntryView> entries,
    Set<String>? allowedViewerIds,
  ) onOpenMyStatuses;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = floatingNavBarClearance;
    final resolvedUid = currentUserId?.trim();
    final mappedEntries = entries
        .map(
          (entry) => _StatusEntryView(
            entry: entry,
            payload: StatusPayload.fromRaw(entry.payload),
          ),
        )
        .toList(growable: false)
      ..sort(
        (left, right) => right.entry.createdAt.compareTo(left.entry.createdAt),
      );
    final myEntries = resolvedUid == null || resolvedUid.isEmpty
        ? <_StatusEntryView>[]
        : mappedEntries
            .where((entry) => entry.entry.author.trim() == resolvedUid)
            .toList(growable: false);
    final otherEntries = resolvedUid == null || resolvedUid.isEmpty
        ? mappedEntries
        : mappedEntries
            .where((entry) => entry.entry.author.trim() != resolvedUid)
            .toList(growable: false);
    final tiles = <Widget>[
      _MyStatusHeaderTile(
        hasEntries: myEntries.isNotEmpty,
        entryCount: myEntries.length,
        onAddStatus: onAddStatus,
        onOpenStatuses: () => onOpenMyStatuses(myEntries, allowedViewerIds),
      ),
      for (final entry in otherEntries)
        _StatusEntryTile(
          entry: entry,
          onOpenStatus: () => onOpenStatus(entry),
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showDemoHint)
                  const MaterialBanner(
                    content: Text(
                      'Status backend is not active for this user yet.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: tiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 0),
                    itemBuilder: (context, index) => tiles[index],
                  ),
                ),
              ],
            ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomClearance),
        child: FloatingActionButton(
          heroTag: 'statusCreateFab',
          onPressed: onAddStatus,
          tooltip: 'Add status',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _MyStatusHeaderTile extends StatelessWidget {
  const _MyStatusHeaderTile({
    required this.hasEntries,
    required this.entryCount,
    required this.onAddStatus,
    required this.onOpenStatuses,
  });

  final bool hasEntries;
  final int entryCount;
  final VoidCallback onAddStatus;
  final VoidCallback onOpenStatuses;

  @override
  Widget build(BuildContext context) {
    final subtitle = hasEntries
        ? '$entryCount update${entryCount == 1 ? '' : 's'}'
        : 'Use + to add a status update';
    return ListTile(
      leading: CircleAvatar(
        child: Icon(hasEntries ? Icons.person : Icons.add),
      ),
      title: const Text('My status'),
      subtitle: Text(subtitle),
      onTap: hasEntries ? onOpenStatuses : onAddStatus,
    );
  }
}

class _MyStatusEntryTile extends StatelessWidget {
  const _MyStatusEntryTile({
    required this.entry,
    required this.allowedViewerIds,
    required this.onOpenStatus,
    required this.onLongPress,
  });

  final _StatusEntryView entry;
  final Set<String>? allowedViewerIds;
  final VoidCallback onOpenStatus;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final stream = Firebase.apps.isEmpty || entry.entry.id.trim().isEmpty
        ? null
        : FirebaseFirestore.instance
            .collection(FirebasePaths.status)
            .doc(entry.entry.author)
            .collection(FirebasePaths.items)
            .doc(entry.entry.id)
            .snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final viewers =
            _viewerIdsFromSnapshot(snapshot.data, entry.entry.author);
        final filtered = allowedViewerIds == null
            ? viewers
            : viewers.where(allowedViewerIds!.contains).toList();
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.auto_stories)),
          title: Text(_buildStatusSummary(entry.payload)),
          subtitle: Text(_formatStatusAge(entry.entry.createdAt)),
          trailing: _ViewersButton(
            count: filtered.length,
            onTap: () => _showViewersSheet(context, filtered),
          ),
          onTap: onOpenStatus,
          onLongPress: onLongPress,
        );
      },
    );
  }
}

class _StatusEntryTile extends StatelessWidget {
  const _StatusEntryTile({
    required this.entry,
    required this.onOpenStatus,
  });

  final _StatusEntryView entry;
  final VoidCallback onOpenStatus;

  @override
  Widget build(BuildContext context) {
    final avatarLetter = entry.entry.author.isEmpty
        ? '?'
        : entry.entry.author[0].toUpperCase();
    return ListTile(
      leading: CircleAvatar(child: Text(avatarLetter)),
      title: _AuthorLabel(authorId: entry.entry.author),
      subtitle: _StatusSummaryTile(
        payload: entry.payload,
        createdAt: entry.entry.createdAt,
      ),
      isThreeLine: true,
      onTap: onOpenStatus,
    );
  }
}

class _MyStatusListPage extends StatefulWidget {
  const _MyStatusListPage({
    required this.entries,
    required this.allowedViewerIds,
    required this.onOpenStatus,
    required this.onAddStatus,
    required this.onEditStatus,
    required this.onDeleteStatus,
  });

  final List<_StatusEntryView> entries;
  final Set<String>? allowedViewerIds;
  final void Function(_StatusEntryView entry) onOpenStatus;
  final Future<void> Function() onAddStatus;
  final Future<StatusPayload?> Function(_StatusEntryView entry) onEditStatus;
  final Future<bool> Function(_StatusEntryView entry) onDeleteStatus;

  @override
  State<_MyStatusListPage> createState() => _MyStatusListPageState();
}

class _MyStatusListPageState extends State<_MyStatusListPage> {
  late List<_StatusEntryView> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries.toList(growable: true);
    _sortEntries();
  }

  @override
  void didUpdateWidget(covariant _MyStatusListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _entries = widget.entries.toList(growable: true);
      _sortEntries();
    }
  }

  void _sortEntries() {
    _entries.sort(
      (left, right) => right.entry.createdAt.compareTo(left.entry.createdAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('My status')),
      body: sorted.isEmpty
          ? const Center(child: Text('No status updates yet'))
          : ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final entry = sorted[index];
                return _MyStatusEntryTile(
                  entry: entry,
                  allowedViewerIds: widget.allowedViewerIds,
                  onOpenStatus: () => widget.onOpenStatus(entry),
                  onLongPress: () => _showEntryActions(context, entry),
                );
              },
            ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: floatingNavBarClearance),
        child: FloatingActionButton(
          heroTag: 'statusCreateFabMyList',
          onPressed: widget.onAddStatus,
          tooltip: 'Add status',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showEntryActions(BuildContext context, _StatusEntryView entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit status'),
              onTap: () async {
                Navigator.of(context).pop();
                final updated = await widget.onEditStatus(entry);
                if (updated != null && mounted) {
                  setState(() {
                    final index = _entries.indexWhere(
                      (item) => item.entry.id == entry.entry.id,
                    );
                    if (index >= 0) {
                      _entries[index] = _StatusEntryView(
                        entry: entry.entry,
                        payload: updated,
                      );
                    }
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete status'),
              onTap: () async {
                Navigator.of(context).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete status?'),
                    content: const Text('This status will be removed for everyone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final success = await widget.onDeleteStatus(entry);
                  if (success && mounted) {
                    setState(() {
                      _entries.removeWhere(
                        (item) => item.entry.id == entry.entry.id,
                      );
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorLabel extends StatelessWidget {
  const _AuthorLabel({required this.authorId, this.style});

  final String authorId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolveAuthorLabel(authorId),
      builder: (context, snapshot) {
        final label = snapshot.data?.trim();
        final resolved =
            (label == null || label.isEmpty) ? authorId : label;
        return Text(
          resolved,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class _ViewersButton extends StatelessWidget {
  const _ViewersButton({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.remove_red_eye_outlined, size: 18),
            const SizedBox(width: 4),
            Text('$count'),
          ],
        ),
      ),
    );
  }
}

void _showViewersSheet(BuildContext context, List<String> viewerIds) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: viewerIds.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No views yet'),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: viewerIds.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final viewerId = viewerIds[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: _AuthorLabel(authorId: viewerId),
                );
              },
            ),
    ),
  );
}

List<String> _viewerIdsFromSnapshot(
  DocumentSnapshot<Map<String, dynamic>>? snapshot,
  String authorId,
) {
  final data = snapshot?.data();
  final raw = data?['viewedByUserIds'];
  if (raw is! List) {
    return const <String>[];
  }
  final viewers = raw
      .map((entry) => entry?.toString().trim() ?? '')
      .where((id) => id.isNotEmpty && id != authorId)
      .toList(growable: false);
  return viewers;
}

class _LocalStatusEntry {
  _LocalStatusEntry({
    required this.id,
    required this.author,
    required this.payload,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String author;
  final String payload;
  final DateTime createdAt;
}

class _StatusEntryView {
  const _StatusEntryView({required this.entry, required this.payload});

  final _LocalStatusEntry entry;
  final StatusPayload payload;
}

String _buildStatusSummary(StatusPayload payload) {
  switch (payload.type) {
    case StatusPayloadType.image:
      return payload.caption?.isNotEmpty == true ? payload.caption! : 'Photo';
    case StatusPayloadType.video:
      return payload.caption?.isNotEmpty == true ? payload.caption! : 'Video';
    case StatusPayloadType.text:
      final text = payload.text.trim();
      return text.isEmpty ? 'Text status' : text;
  }
}

String _formatStatusAge(DateTime createdAt) {
  final now = DateTime.now();
  final diff = now.difference(createdAt);
  if (diff.inMinutes < 1) {
    return 'Just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} min ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} h ago';
  }
  return '${diff.inDays} d ago';
}

class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.payload,
    required this.createdAt,
  });

  final StatusPayload payload;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final summary = _buildStatusSummary(payload);
    final age = _formatStatusAge(createdAt);
    final icon = switch (payload.type) {
      StatusPayloadType.text => Icons.text_fields,
      StatusPayloadType.image => Icons.image_outlined,
      StatusPayloadType.video => Icons.videocam_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Theme.of(context).hintColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (payload.musicUrl != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.music_note, size: 14),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          age,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusViewer extends StatefulWidget {
  const _StatusViewer({required this.entry});

  final _StatusEntryView entry;

  @override
  State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer> {
  AudioPlayer? _audioPlayer;
  Timer? _audioStopper;
  VideoPlayerController? _videoController;
  Future<void>? _videoInit;
  late final Future<String> _authorLabelFuture;
  bool _navHidden = false;

  @override
  void initState() {
    super.initState();
    _authorLabelFuture = _resolveAuthorLabel(widget.entry.entry.author);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      BottomNavVisibilityController.hide();
      _navHidden = true;
    });
    _startAudioIfNeeded();
    _startVideoIfNeeded();
    _markViewed();
  }

  @override
  void dispose() {
    if (_navHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        BottomNavVisibilityController.show();
      });
    }
    _audioStopper?.cancel();
    _audioPlayer?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _markViewed() async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null || viewerId.isEmpty) {
      return;
    }
    if (viewerId == widget.entry.entry.author) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(FirebasePaths.status)
          .doc(widget.entry.entry.author)
          .collection(FirebasePaths.items)
          .doc(widget.entry.entry.id)
          .set({
            'viewedByUserIds': FieldValue.arrayUnion([viewerId]),
            'lastViewedAt': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _startAudioIfNeeded() {
    final url = widget.entry.payload.musicUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    final player = AudioPlayer();
    _audioPlayer = player;
    unawaited(() async {
      try {
        await player.setUrl(url);
        await player.play();
        final durationSeconds = widget.entry.payload.musicDurationSeconds ??
            StatusPayloadDefaults.musicDurationSeconds;
        _audioStopper = Timer(
          Duration(seconds: durationSeconds),
          () => player.stop(),
        );
      } catch (_) {}
    }());
  }

  void _startVideoIfNeeded() {
    final payload = widget.entry.payload;
    if (payload.type != StatusPayloadType.video) {
      return;
    }
    final url = payload.mediaUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    _videoInit = controller.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      setState(() {});
      await controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.entry.payload;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(payload)),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<String>(
                          future: _authorLabelFuture,
                          builder: (context, snapshot) {
                            final label = snapshot.data?.trim();
                            final resolved =
                                (label == null || label.isEmpty)
                                    ? widget.entry.entry.author
                                    : label;
                            return Text(
                              resolved,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                        Text(
                          _formatStatusAge(widget.entry.entry.createdAt),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (payload.musicUrl != null)
                    const Icon(Icons.music_note, color: Colors.white),
                ],
              ),
            ),
            if ((payload.caption ?? '').trim().isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    payload.caption!.trim(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(StatusPayload payload) {
    switch (payload.type) {
      case StatusPayloadType.text:
        final background =
            payload.backgroundColor ?? StatusPayloadDefaults.backgroundColor;
        final foreground =
            payload.textColor ?? StatusPayloadDefaults.textColor;
        return Container(
          color: background,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            payload.text.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case StatusPayloadType.image:
        final url = payload.mediaUrl;
        if (url == null || url.isEmpty) {
          return const Center(
            child: Text(
              'Image is unavailable',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return Image.network(url, fit: BoxFit.cover);
      case StatusPayloadType.video:
        if (_videoController == null || _videoInit == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return FutureBuilder<void>(
          future: _videoInit,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                !_videoController!.value.isInitialized) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            );
          },
        );
    }
  }
}

class _TextStatusDialog extends StatefulWidget {
  const _TextStatusDialog({
    this.initialText,
    this.initialBackgroundColor,
    this.initialTextColor,
    this.existingMusicUrl,
  });

  final String? initialText;
  final Color? initialBackgroundColor;
  final Color? initialTextColor;
  final String? existingMusicUrl;

  @override
  State<_TextStatusDialog> createState() => _TextStatusDialogState();
}

class _TextStatusDialogState extends State<_TextStatusDialog> {
  final TextEditingController _controller = TextEditingController();
  Color _backgroundColor = StatusPayloadDefaults.backgroundColor;
  Color _textColor = StatusPayloadDefaults.textColor;
  PlatformFile? _musicFile;
  bool _removeExistingMusic = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialText?.trim();
    if (initialText != null && initialText.isNotEmpty) {
      _controller.text = initialText;
    }
    _backgroundColor =
        widget.initialBackgroundColor ?? StatusPayloadDefaults.backgroundColor;
    _textColor = widget.initialTextColor ?? StatusPayloadDefaults.textColor;
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('New status'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Write a quick update',
              ),
            ),
            const SizedBox(height: 12),
            const Text('Background'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statusBackgroundPalette
                  .map(
                    (color) => _ColorDot(
                      color: color,
                      selected: _backgroundColor == color,
                      onTap: () => setState(() => _backgroundColor = color),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            const Text('Text color'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statusTextPalette
                  .map(
                    (color) => _ColorDot(
                      color: color,
                      selected: _textColor == color,
                      onTap: () => setState(() => _textColor = color),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _musicLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ..._musicActions(),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(
                    _TextStatusInput(
                      text: _controller.text,
                      backgroundColor: _backgroundColor,
                      textColor: _textColor,
                      musicFile: _musicFile,
                      removeExistingMusic: _removeExistingMusic,
                    ),
                  )
              : null,
          child: const Text('Post'),
        ),
      ],
    );
  }

  Future<void> _pickMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
      withData: kIsWeb,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _musicFile = result?.files.single;
      _removeExistingMusic = false;
    });
  }

  String _musicLabel() {
    if (_musicFile != null) {
      return 'Music: ${_musicFile!.name}';
    }
    final hasExisting = widget.existingMusicUrl?.trim().isNotEmpty == true;
    if (hasExisting && !_removeExistingMusic) {
      return 'Music: attached';
    }
    if (hasExisting && _removeExistingMusic) {
      return 'Music removed';
    }
    return 'Optional music (30s)';
  }

  List<Widget> _musicActions() {
    final hasExisting = widget.existingMusicUrl?.trim().isNotEmpty == true;
    if (_musicFile != null) {
      return [
        TextButton(
          onPressed: _pickMusic,
          child: const Text('Replace'),
        ),
        IconButton(
          onPressed: () => setState(() => _musicFile = null),
          icon: const Icon(Icons.close),
        ),
      ];
    }
    if (hasExisting && !_removeExistingMusic) {
      return [
        TextButton(
          onPressed: _pickMusic,
          child: const Text('Replace'),
        ),
        TextButton(
          onPressed: () => setState(() => _removeExistingMusic = true),
          child: const Text('Remove'),
        ),
      ];
    }
    if (hasExisting && _removeExistingMusic) {
      return [
        TextButton(
          onPressed: () => setState(() => _removeExistingMusic = false),
          child: const Text('Undo'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _pickMusic,
        child: const Text('Add'),
      ),
    ];
  }
}

class _MediaStatusDialog extends StatefulWidget {
  const _MediaStatusDialog({
    required this.allowMusic,
    this.initialCaption,
    this.existingMusicUrl,
  });

  final bool allowMusic;
  final String? initialCaption;
  final String? existingMusicUrl;

  @override
  State<_MediaStatusDialog> createState() => _MediaStatusDialogState();
}

class _MediaStatusDialogState extends State<_MediaStatusDialog> {
  final TextEditingController _captionController = TextEditingController();
  PlatformFile? _musicFile;
  bool _removeExistingMusic = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final initialCaption = widget.initialCaption?.trim();
    if (initialCaption != null && initialCaption.isNotEmpty) {
      _captionController.text = initialCaption;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Status details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _captionController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Add a caption (optional)',
              ),
            ),
            if (widget.allowMusic) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _musicLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ..._musicActions(),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _MediaStatusInput(
              caption: _captionController.text,
              musicFile: _musicFile,
              removeExistingMusic: _removeExistingMusic,
            ),
          ),
          child: const Text('Post'),
        ),
      ],
    );
  }

  Future<void> _pickMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
      withData: kIsWeb,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _musicFile = result?.files.single;
      _removeExistingMusic = false;
    });
  }

  String _musicLabel() {
    if (_musicFile != null) {
      return 'Music: ${_musicFile!.name}';
    }
    final hasExisting = widget.existingMusicUrl?.trim().isNotEmpty == true;
    if (hasExisting && !_removeExistingMusic) {
      return 'Music: attached';
    }
    if (hasExisting && _removeExistingMusic) {
      return 'Music removed';
    }
    return 'Optional music (30s)';
  }

  List<Widget> _musicActions() {
    final hasExisting = widget.existingMusicUrl?.trim().isNotEmpty == true;
    if (_musicFile != null) {
      return [
        TextButton(
          onPressed: _pickMusic,
          child: const Text('Replace'),
        ),
        IconButton(
          onPressed: () => setState(() => _musicFile = null),
          icon: const Icon(Icons.close),
        ),
      ];
    }
    if (hasExisting && !_removeExistingMusic) {
      return [
        TextButton(
          onPressed: _pickMusic,
          child: const Text('Replace'),
        ),
        TextButton(
          onPressed: () => setState(() => _removeExistingMusic = true),
          child: const Text('Remove'),
        ),
      ];
    }
    if (hasExisting && _removeExistingMusic) {
      return [
        TextButton(
          onPressed: () => setState(() => _removeExistingMusic = false),
          child: const Text('Undo'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _pickMusic,
        child: const Text('Add'),
      ),
    ];
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Colors.black87 : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _TextStatusInput {
  const _TextStatusInput({
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    required this.musicFile,
    required this.removeExistingMusic,
  });

  final String text;
  final Color backgroundColor;
  final Color textColor;
  final PlatformFile? musicFile;
  final bool removeExistingMusic;
}

class _MediaStatusInput {
  const _MediaStatusInput({
    required this.caption,
    required this.musicFile,
    required this.removeExistingMusic,
  });

  final String? caption;
  final PlatformFile? musicFile;
  final bool removeExistingMusic;
}

class _StatusDraft {
  const _StatusDraft({required this.payload, required this.mediaType});

  final StatusPayload payload;
  final String mediaType;
}

enum _StatusComposerChoice { text, image, video }
