import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/floating_nav_metrics.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/features/status/domain/usecases/create_status_use_case.dart';
import 'package:chatify/features/status/presentation/bloc/status_cubit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final List<_LocalStatusEntry> _localEntries = [
    _LocalStatusEntry(author: 'Alice', content: 'Sprint update ready'),
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
      return _StatusScaffold(
        entries: _localEntries,
        loading: false,
        showDemoHint: true,
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
                  author: item.authorId,
                  content: item.ciphertextRef,
                  createdAt: item.createdAt,
                ),
              )
              .toList();
          return _StatusScaffold(
            entries: entries,
            loading: state.loading,
            showDemoHint: entries.isEmpty && !state.loading,
            onAddStatus: _createWiredStatus,
          );
        },
      ),
    );
  }

  Future<void> _createWiredStatus() async {
    final value = await _promptStatusText();
    if (!mounted || value == null || value.trim().isEmpty) {
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
          mediaType: 'text',
          ciphertextRef: value.trim(),
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
    final value = await _promptStatusText();
    if (!mounted || value == null || value.trim().isEmpty) {
      return;
    }
    setState(() {
      _localEntries.insert(
        0,
        _LocalStatusEntry(
          author: _resolveAuthorId(),
          content: value.trim(),
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<String?> _promptStatusText() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New status'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Write a quick update'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _resolveAuthorId() {
    if (!getIt.isRegistered<FirebaseAuth>()) {
      return 'local-debug-user';
    }
    return getIt<FirebaseAuth>().currentUser?.uid ?? 'local-debug-user';
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
    required this.onAddStatus,
  });

  final List<_LocalStatusEntry> entries;
  final bool loading;
  final bool showDemoHint;
  final Future<void> Function() onAddStatus;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = floatingNavBarClearance;
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
                    itemCount: entries.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const ListTile(
                          leading: CircleAvatar(child: Icon(Icons.add)),
                          title: Text('My status'),
                          subtitle: Text('Use + to add a status update'),
                        );
                      }
                      final item = entries[index - 1];
                      final avatarLetter = item.author.isEmpty
                          ? '?'
                          : item.author[0].toUpperCase();
                      return ListTile(
                        leading: CircleAvatar(child: Text(avatarLetter)),
                        title: Text(item.author),
                        subtitle: Text(
                          '${item.content}\n${_formatAge(item.createdAt)}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomClearance),
        child: FloatingActionButton(
          onPressed: onAddStatus,
          tooltip: 'Add status',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  String _formatAge(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} h ago';
    }
    return '${diff.inDays} d ago';
  }
}

class _LocalStatusEntry {
  _LocalStatusEntry({
    required this.author,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String author;
  final String content;
  final DateTime createdAt;
}
