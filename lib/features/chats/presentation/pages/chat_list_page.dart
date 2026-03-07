import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/conversation.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:chatify/features/chats/presentation/bloc/chats_cubit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  bool _showArchivedOnly = false;

  bool get _hasWiredChats =>
      getIt.isRegistered<ChatsCubit>() &&
      getIt.isRegistered<ConversationRepository>() &&
      Firebase.apps.isNotEmpty;

  bool get _hasActiveFirebaseUser =>
      Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null;

  static const List<_ChatListItem> _demoItems = [
    _ChatListItem(
      title: 'Alice',
      subtitle: 'Let us finalize release notes.',
      conversationId: 'c_demo_1',
      trailing: '10:42',
    ),
    _ChatListItem(
      title: 'Family',
      subtitle: 'Dinner at 9 PM',
      conversationId: 'c_demo_2',
      trailing: '09:15',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredChats) {
      return _ChatsScaffold(
        items: _demoItems,
        loading: false,
        showDemoHint: true,
        showArchivedOnly: false,
        archivedCount: 0,
        onOpenConversation: (id) => context.push('/chat/$id'),
        onConversationLongPress: (_) {},
        onSearch: () => context.push('/search'),
        onToggleArchivedView: () {},
        onCreate: _openDemoConversation,
      );
    }

    return BlocProvider(
      create: (_) => getIt<ChatsCubit>(),
      child: BlocConsumer<ChatsCubit, ChatsState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage &&
            current.errorMessage != null,
        listener: (context, state) {
          final message = state.errorMessage;
          if (message == null || !mounted) {
            return;
          }
          _showSnack(message);
          context.read<ChatsCubit>().clearError();
        },
        builder: (context, state) {
          final mappedItems = state.items.map(_fromConversation).toList();
          final activeItems = mappedItems
              .where((item) => !item.isArchived)
              .toList();
          final archivedItems = mappedItems
              .where((item) => item.isArchived)
              .toList();
          final items = _showArchivedOnly ? archivedItems : activeItems;
          return _ChatsScaffold(
            items: items,
            loading: state.loading,
            showDemoHint: false,
            showArchivedOnly: _showArchivedOnly,
            archivedCount: archivedItems.length,
            emptyMessage: _showArchivedOnly
                ? 'No archived conversations.'
                : 'No conversations yet. Create one to start chatting.',
            onOpenConversation: (id) => context.push('/chat/$id'),
            onConversationLongPress: _openConversationActions,
            onSearch: () => context.push('/search'),
            onToggleArchivedView: () {
              setState(() {
                _showArchivedOnly = !_showArchivedOnly;
              });
            },
            onCreate: _openCreateConversationMenu,
          );
        },
      ),
    );
  }

  _ChatListItem _fromConversation(Conversation conversation) {
    final title = (conversation.title != null && conversation.title!.isNotEmpty)
        ? conversation.title!
        : conversation.type == ConversationType.group
        ? 'Group ${conversation.id.substring(0, 6)}'
        : 'Direct chat';
    final subtitle = conversation.type == ConversationType.group
        ? 'Group conversation'
        : 'Private conversation';
    final trailing = conversation.updatedAt == null
        ? ''
        : _formatTime(conversation.updatedAt!);
    return _ChatListItem(
      title: title,
      subtitle: subtitle,
      conversationId: conversation.id,
      trailing: trailing,
      isArchived: conversation.isArchived,
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _openCreateConversationMenu() async {
    if (!_hasActiveFirebaseUser) {
      _showSnack('Sign in first before creating a conversation');
      return;
    }

    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('New direct chat'),
                onTap: () => Navigator.of(context).pop('direct'),
              ),
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('New group'),
                onTap: () => Navigator.of(context).pop('group'),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Open demo chat'),
                onTap: () => Navigator.of(context).pop('demo'),
              ),
            ],
          ),
        ),
      );

      if (!mounted || action == null) {
        return;
      }

      if (action == 'direct') {
        await _createDirectConversation();
        return;
      }
      if (action == 'group') {
        await _createGroupConversation();
        return;
      }
      _openDemoConversation();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to open chat creation: $error');
    }
  }

  Future<void> _createDirectConversation() async {
    final peerController = TextEditingController();
    try {
      final peerUserId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New direct chat'),
          content: TextField(
            controller: peerController,
            decoration: const InputDecoration(
              labelText: 'Peer user id or phone',
              hintText: 'uid_123 or +2010XXXXXXXX',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(peerController.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );

      if (!mounted || peerUserId == null || peerUserId.trim().isEmpty) {
        return;
      }

      final repository = _resolveConversationRepository();
      if (repository == null) {
        _showSnack('Conversation service is unavailable right now');
        return;
      }

      final result = await repository.createDirectConversation(
        peerUserId: peerUserId.trim(),
      );
      if (!mounted) {
        return;
      }
      if (result is Success<String>) {
        context.push('/chat/${result.value}');
        return;
      }
      _showSnack(
        result.error?.message ?? 'Failed to create direct conversation',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to create direct conversation: $error');
    } finally {
      peerController.dispose();
    }
  }

  Future<void> _createGroupConversation() async {
    final titleController = TextEditingController();
    final membersController = TextEditingController();
    try {
      final payload = await showDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Group title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: membersController,
                decoration: const InputDecoration(
                  labelText: 'Members',
                  hintText: 'uid_1, uid_2',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop((titleController.text, membersController.text)),
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
      final members = payload.$2
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (members.isEmpty) {
        _showSnack('Add at least one member user id');
        return;
      }

      final repository = _resolveConversationRepository();
      if (repository == null) {
        _showSnack('Conversation service is unavailable right now');
        return;
      }

      final result = await repository.createGroup(
        title: title,
        memberUserIds: members,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<String>) {
        context.push('/chat/${result.value}');
        return;
      }
      _showSnack(
        result.error?.message ?? 'Failed to create group conversation',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to create group conversation: $error');
    } finally {
      titleController.dispose();
      membersController.dispose();
    }
  }

  void _openDemoConversation() {
    context.push('/chat/c_demo_1');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openConversationActions(_ChatListItem item) async {
    if (!_hasActiveFirebaseUser) {
      _showSnack('Sign in first before managing conversations');
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                item.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(item.isArchived ? 'Unarchive chat' : 'Archive chat'),
              subtitle: Text(item.title),
              onTap: () => Navigator.of(
                context,
              ).pop(item.isArchived ? 'unarchive' : 'archive'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete conversation'),
              subtitle: Text(item.title),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    final repository = _resolveConversationRepository();
    if (repository == null) {
      _showSnack('Conversation service is unavailable right now');
      return;
    }

    if (action == 'archive' || action == 'unarchive') {
      final archived = action == 'archive';
      final result = await repository.setConversationArchived(
        conversationId: item.conversationId,
        archived: archived,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        _showSnack(archived ? 'Chat archived' : 'Chat unarchived');
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to update archive state');
      return;
    }

    if (action != 'delete') {
      return;
    }

    final scope = await showModalBottomSheet<_ConversationDeleteScope>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Delete for me'),
              onTap: () =>
                  Navigator.of(context).pop(_ConversationDeleteScope.forMe),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Delete for everyone'),
              onTap: () => Navigator.of(
                context,
              ).pop(_ConversationDeleteScope.forEveryone),
            ),
          ],
        ),
      ),
    );
    if (!mounted || scope == null) {
      return;
    }

    final result = scope == _ConversationDeleteScope.forMe
        ? await repository.deleteConversationForMe(
            conversationId: item.conversationId,
          )
        : await repository.deleteConversation(
            conversationId: item.conversationId,
          );
    if (!mounted) {
      return;
    }
    if (result is Success<void>) {
      final label = scope == _ConversationDeleteScope.forMe
          ? 'Conversation deleted for you'
          : 'Conversation deleted for everyone';
      _showSnack(label);
      return;
    }
    _showSnack(result.error?.message ?? 'Failed to delete conversation');
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
}

class _ChatsScaffold extends StatelessWidget {
  const _ChatsScaffold({
    required this.items,
    required this.loading,
    required this.showDemoHint,
    required this.showArchivedOnly,
    required this.archivedCount,
    this.emptyMessage,
    required this.onOpenConversation,
    required this.onConversationLongPress,
    required this.onSearch,
    required this.onToggleArchivedView,
    required this.onCreate,
  });

  final List<_ChatListItem> items;
  final bool loading;
  final bool showDemoHint;
  final bool showArchivedOnly;
  final int archivedCount;
  final String? emptyMessage;
  final void Function(String id) onOpenConversation;
  final void Function(_ChatListItem item) onConversationLongPress;
  final VoidCallback onSearch;
  final VoidCallback onToggleArchivedView;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(showArchivedOnly ? 'Archived chats' : 'Chats'),
        actions: [
          IconButton(
            onPressed: onToggleArchivedView,
            icon: Icon(
              showArchivedOnly ? Icons.inbox_outlined : Icons.archive_outlined,
            ),
            tooltip: showArchivedOnly
                ? 'Back to chats'
                : 'Archived chats ($archivedCount)',
          ),
          IconButton(onPressed: onSearch, icon: const Icon(Icons.search)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showDemoHint)
                  const MaterialBanner(
                    content: Text(
                      'No conversations found yet. Showing demo entries for quick testing.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            emptyMessage ?? 'No conversations found.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 0),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(item.title[0])),
                              title: Text(item.title),
                              subtitle: Text(item.subtitle),
                              trailing: item.trailing.isEmpty
                                  ? null
                                  : Text(item.trailing),
                              onTap: () =>
                                  onOpenConversation(item.conversationId),
                              onLongPress: () => onConversationLongPress(item),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: onCreate,
        tooltip: 'New chat',
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}

class _ChatListItem {
  const _ChatListItem({
    required this.title,
    required this.subtitle,
    required this.conversationId,
    required this.trailing,
    this.isArchived = false,
  });

  final String title;
  final String subtitle;
  final String conversationId;
  final String trailing;
  final bool isArchived;
}

enum _ConversationDeleteScope { forMe, forEveryone }
