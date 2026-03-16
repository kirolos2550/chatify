import 'dart:math';

import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/floating_nav_metrics.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/common/bottom_nav_visibility.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:chatify/features/chats/presentation/bloc/chats_cubit.dart';
import 'package:chatify/features/chats/presentation/models/chat_discovery_item.dart';
import 'package:chatify/features/chats/presentation/widgets/direct_chat_sheet.dart';
import 'package:chatify/features/chats/presentation/widgets/group_creation_sheet.dart';
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
  ChatListFilter _selectedFilter = ChatListFilter.all;
  String? _selectedList;
  List<String> _localLists = <String>[];
  final Map<String, List<String>> _listOverrides =
      <String, List<String>>{};

  bool get _hasWiredChats =>
      getIt.isRegistered<ChatsCubit>() &&
      getIt.isRegistered<ConversationRepository>() &&
      Firebase.apps.isNotEmpty;

  bool get _hasActiveFirebaseUser =>
      Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null;

  static const List<ChatDiscoveryItem> _demoItems = [
    ChatDiscoveryItem(
      title: 'Alice',
      subtitle: '+201001112223',
      conversationId: 'c_demo_1',
      trailing: '10:42',
    ),
    ChatDiscoveryItem(
      title: 'Family',
      subtitle: 'Dinner at 9 PM',
      conversationId: 'c_demo_2',
      trailing: '09:15',
      unreadCount: 2,
      lists: ['Family'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredChats) {
      final availableLists = _mergeAvailableLists(
        explicitLists: _localLists,
        items: _demoItems,
      );
      final selectedList = availableLists.any(
            (list) => list.toLowerCase() == _selectedList?.toLowerCase(),
          )
          ? _selectedList
          : null;
      final filteredDemoItems = filterChatDiscoveryItems(
        items: _demoItems,
        filter: _selectedFilter,
        list: selectedList,
      );
      return _ChatsScaffold(
        items: filteredDemoItems,
        loading: false,
        showDemoHint: true,
        showArchivedOnly: false,
        archivedCount: 0,
        totalUnreadCount: 0,
        selectedFilter: _selectedFilter,
        selectedList: selectedList,
        availableLists: availableLists,
        onOpenConversation: (id) => context.push('/chat/$id'),
        onConversationLongPress: (item, availableLists) {},
        onSearch: () => context.push('/search'),
        onToggleArchivedView: () {},
        onFilterChanged: _updateFilter,
        onListChanged: _updateList,
        onCreateList: () => _createList(availableLists),
        onCreate: _openDemoConversation,
      );
    }

    final repository = _resolveConversationRepository();
    if (repository == null) {
      return const SizedBox.shrink();
    }

    return BlocProvider(
      create: (_) => getIt<ChatsCubit>(),
      child: StreamBuilder<List<String>>(
        stream: repository.watchConversationLists(),
        initialData: const <String>[],
        builder: (context, listsSnapshot) => BlocConsumer<ChatsCubit, ChatsState>(
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
            final mappedItems = _applyListOverrides(
              state.items.map(mapConversationToChatDiscoveryItem).toList(),
            );
            final activeItems = mappedItems
                .where((item) => !item.isArchived)
                .toList();
            final archivedItems = mappedItems
                .where((item) => item.isArchived)
                .toList();
            final sourceItems = _showArchivedOnly ? archivedItems : activeItems;
            final availableLists = _mergeAvailableLists(
              explicitLists: [
                ...?listsSnapshot.data,
                ..._localLists,
              ],
              items: mappedItems,
            );
            final selectedList = availableLists.any(
                  (list) => list.toLowerCase() == _selectedList?.toLowerCase(),
                )
                ? _selectedList
                : null;
            final items = filterChatDiscoveryItems(
              items: sourceItems,
              filter: _selectedFilter,
              list: selectedList,
            );
            final totalUnreadCount = activeItems.fold<int>(
              0,
              (total, item) => total + item.unreadCount,
            );
            return _ChatsScaffold(
              items: items,
              loading: state.loading || listsSnapshot.connectionState == ConnectionState.waiting,
              showDemoHint: false,
              showArchivedOnly: _showArchivedOnly,
              archivedCount: archivedItems.length,
              totalUnreadCount: totalUnreadCount,
              selectedFilter: _selectedFilter,
              selectedList: selectedList,
              availableLists: availableLists,
              emptyMessage: _showArchivedOnly
                  ? 'No archived conversations.'
                  : _buildEmptyMessage(),
              onOpenConversation: (id) => context.push('/chat/$id'),
              onConversationLongPress: (item, availableLists) =>
                  _openConversationActions(item, availableLists),
              onSearch: () => context.push('/search'),
              onToggleArchivedView: () {
                setState(() {
                  _showArchivedOnly = !_showArchivedOnly;
                  _selectedList = null;
                });
              },
              onFilterChanged: _updateFilter,
              onListChanged: _updateList,
              onCreateList: () => _createList(availableLists),
              onCreate: _openCreateConversationMenu,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreateConversationMenu() async {
    if (!_hasActiveFirebaseUser) {
      _showSnack('Sign in first before creating a conversation');
      return;
    }

    try {
      final action = await BottomNavVisibilityController.runWithHidden(
        () => showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          builder: (context) => _ResponsiveActionSheet(
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
    final conversationRepository = _resolveConversationRepository();
    if (conversationRepository == null) {
      _showSnack('Conversation service is unavailable right now');
      return;
    }
    final contactsRepository = _resolveContactsRepository();
    if (contactsRepository == null) {
      _showSnack('Contacts service is unavailable right now');
      return;
    }

    try {
      final peerUserId = await showDirectChatSheet(
        context: context,
        contactsRepository: contactsRepository,
      );

      if (!mounted || peerUserId == null || peerUserId.trim().isEmpty) {
        return;
      }

      final result = await conversationRepository.createDirectConversation(
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
    }
  }

  Future<void> _createGroupConversation() async {
    final conversationRepository = _resolveConversationRepository();
    if (conversationRepository == null) {
      _showSnack('Conversation service is unavailable right now');
      return;
    }
    final contactsRepository = _resolveContactsRepository();
    if (contactsRepository == null) {
      _showSnack('Contacts service is unavailable right now');
      return;
    }

    try {
      final draft = await showGroupCreationSheet(
        context: context,
        contactsRepository: contactsRepository,
        title: 'Create group',
      );
      if (!mounted || draft == null) {
        return;
      }
      final result = await conversationRepository.createGroup(
        title: draft.title,
        memberUserIds: draft.memberIdentifiers,
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
    }
  }

  void _openDemoConversation() {
    context.push('/chat/c_demo_1');
  }

  List<String> _mergeAvailableLists({
    required List<String> explicitLists,
    required List<ChatDiscoveryItem> items,
  }) {
    return _normalizeListNames([
      ...explicitLists,
      ...collectChatLists(items),
    ]);
  }

  Future<void> _createList(List<String> existingLists) async {
    final controller = TextEditingController();
    try {
      final createdName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Example: Family, Work, VIP',
            ),
            onSubmitted: (_) => Navigator.of(
              context,
            ).pop(_normalizeSingleListName(controller.text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(_normalizeSingleListName(controller.text)),
              child: const Text('Create'),
            ),
          ],
        ),
      );

      final normalizedName = _normalizeSingleListName(createdName);
      if (!mounted || normalizedName == null) {
        return;
      }

      if (existingLists.any(
        (list) => list.toLowerCase() == normalizedName.toLowerCase(),
      )) {
        setState(() => _selectedList = normalizedName);
        return;
      }

      if (_hasWiredChats) {
        final repository = _resolveConversationRepository();
        if (repository == null) {
          _showSnack('Conversation service is unavailable right now');
          return;
        }
        final result = await repository.createConversationList(
          name: normalizedName,
        );
        if (!mounted) {
          return;
        }
        if (result is Success<String>) {
          setState(() {
            _selectedList = result.value;
            _localLists = _normalizeListNames([..._localLists, result.value]);
          });
          _showSnack('List created');
          return;
        }
        _showSnack(result.error?.message ?? 'Failed to create list');
        return;
      }

      setState(() {
        _localLists = _normalizeListNames([..._localLists, normalizedName]);
        _selectedList = normalizedName;
      });
      _showSnack('List created');
    } finally {
      controller.dispose();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddToListSheet(
    ChatDiscoveryItem item,
    List<String> availableLists,
  ) async {
    final repository = _resolveConversationRepository();
    if (repository == null) {
      _showSnack('Conversation service is unavailable right now');
      return;
    }
    try {
      final lists = await BottomNavVisibilityController.runWithHidden(
        () => showModalBottomSheet<List<String>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => _AddToListSheet(
            conversationTitle: item.title,
            selectedLists: item.lists,
            availableLists: availableLists,
          ),
        ),
      );

      if (!mounted || lists == null) {
        return;
      }

      final result = await repository.setConversationLists(
        conversationId: item.conversationId,
        lists: lists,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        setState(() {
          if (lists.isEmpty) {
            _listOverrides.remove(item.conversationId);
          } else {
            _listOverrides[item.conversationId] = _normalizeListNames(lists);
          }
        });
        _showSnack(lists.isEmpty ? 'Removed from all lists' : 'Lists updated');
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to update lists');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to update lists: $error');
    }
  }

  void _updateFilter(ChatListFilter filter) {
    if (!mounted) {
      return;
    }
    setState(() => _selectedFilter = filter);
  }

  void _updateList(String? list) {
    if (!mounted) {
      return;
    }
    setState(() => _selectedList = list);
  }

  List<ChatDiscoveryItem> _applyListOverrides(
    List<ChatDiscoveryItem> items,
  ) {
    if (_listOverrides.isEmpty) {
      return items;
    }

    final updated = <ChatDiscoveryItem>[];
    final toRemove = <String>[];
    for (final item in items) {
      final override = _listOverrides[item.conversationId];
      if (override == null) {
        updated.add(item);
        continue;
      }
      if (_listsMatch(override, item.lists)) {
        updated.add(item);
        toRemove.add(item.conversationId);
        continue;
      }
      updated.add(item.copyWith(lists: override));
    }

    if (toRemove.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          for (final id in toRemove) {
            _listOverrides.remove(id);
          }
        });
      });
    }

    return updated;
  }

  bool _listsMatch(List<String> left, List<String> right) {
    final leftSet = _normalizeListNames(left)
        .map((value) => value.toLowerCase())
        .toSet();
    final rightSet = _normalizeListNames(right)
        .map((value) => value.toLowerCase())
        .toSet();
    if (leftSet.length != rightSet.length) {
      return false;
    }
    for (final value in leftSet) {
      if (!rightSet.contains(value)) {
        return false;
      }
    }
    return true;
  }

  String _buildEmptyMessage() {
    final selectedList = _selectedList?.trim();
    if (_selectedFilter == ChatListFilter.favorites) {
      return 'No favorite conversations yet.';
    }
    if (_selectedFilter == ChatListFilter.unread) {
      return 'No unread conversations right now.';
    }
    if (selectedList != null && selectedList.isNotEmpty) {
      return 'No conversations in list "$selectedList".';
    }
    return 'No conversations yet. Create one to start chatting.';
  }

  Future<void> _openConversationActions(
    ChatDiscoveryItem item,
    List<String> availableLists,
  ) async {
    if (!_hasActiveFirebaseUser) {
      _showSnack('Sign in first before managing conversations');
      return;
    }

    final action = await BottomNavVisibilityController.runWithHidden(
      () => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _ResponsiveActionSheet(
          children: [
            ListTile(
              leading: Icon(
                item.isFavorite ? Icons.star_outline : Icons.star_rounded,
              ),
              title: Text(
                item.isFavorite ? 'Remove from favorites' : 'Add to favorites',
              ),
              subtitle: Text(item.title),
              onTap: () => Navigator.of(
                context,
              ).pop(item.isFavorite ? 'unfavorite' : 'favorite'),
            ),
            ListTile(
              leading: Icon(
                item.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(item.isPinned ? 'Unpin chat' : 'Pin chat'),
              subtitle: Text(item.title),
              onTap: () =>
                  Navigator.of(context).pop(item.isPinned ? 'unpin' : 'pin'),
            ),
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
              leading: const Icon(Icons.playlist_add_outlined),
              title: const Text('Add to list'),
              subtitle: Text(
                item.lists.isEmpty ? 'No list yet' : item.lists.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop('lists'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('Leave group'),
              subtitle: Text(item.title),
              onTap: () => Navigator.of(context).pop('leave_group'),
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

    if (action == 'favorite' || action == 'unfavorite') {
      final favorite = action == 'favorite';
      final result = await repository.setConversationFavorite(
        conversationId: item.conversationId,
        favorite: favorite,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        _showSnack(favorite ? 'Added to favorites' : 'Removed from favorites');
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to update favorites');
      return;
    }

    if (action == 'pin' || action == 'unpin') {
      final pinned = action == 'pin';
      final result = await repository.setConversationPinned(
        conversationId: item.conversationId,
        pinned: pinned,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        _showSnack(pinned ? 'Chat pinned' : 'Chat unpinned');
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to update pin state');
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

    if (action == 'lists') {
      await _openAddToListSheet(item, availableLists);
      return;
    }

    if (action == 'leave_group') {
      final result = await repository.deleteConversationForMe(
        conversationId: item.conversationId,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<void>) {
        _showSnack('You left the group');
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to leave group');
      return;
    }

    if (action != 'delete') {
      return;
    }

    final scope = await BottomNavVisibilityController.runWithHidden(
      () => showModalBottomSheet<_ConversationDeleteScope>(
        context: context,
        useSafeArea: true,
        builder: (context) => _ResponsiveActionSheet(
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

  ContactsRepository? _resolveContactsRepository() {
    if (!getIt.isRegistered<ContactsRepository>()) {
      return null;
    }
    try {
      return getIt<ContactsRepository>();
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
    required this.totalUnreadCount,
    required this.selectedFilter,
    required this.selectedList,
    required this.availableLists,
    this.emptyMessage,
    required this.onOpenConversation,
    required this.onConversationLongPress,
    required this.onSearch,
    required this.onToggleArchivedView,
    required this.onFilterChanged,
    required this.onListChanged,
    required this.onCreateList,
    required this.onCreate,
  });

  final List<ChatDiscoveryItem> items;
  final bool loading;
  final bool showDemoHint;
  final bool showArchivedOnly;
  final int archivedCount;
  final int totalUnreadCount;
  final ChatListFilter selectedFilter;
  final String? selectedList;
  final List<String> availableLists;
  final String? emptyMessage;
  final void Function(String id) onOpenConversation;
  final void Function(ChatDiscoveryItem item, List<String> availableLists)
  onConversationLongPress;
  final VoidCallback onSearch;
  final VoidCallback onToggleArchivedView;
  final ValueChanged<ChatListFilter> onFilterChanged;
  final ValueChanged<String?> onListChanged;
  final VoidCallback onCreateList;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final title = showArchivedOnly
        ? 'Archived chats'
        : totalUnreadCount > 0
        ? 'Chats ($totalUnreadCount)'
        : 'Chats';
    final bottomClearance = floatingNavBarClearance;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(title),
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
                _ChatFilterBar(
                  selectedFilter: selectedFilter,
                  selectedList: selectedList,
                  availableLists: availableLists,
                  onFilterChanged: onFilterChanged,
                  onListChanged: onListChanged,
                  onCreateList: onCreateList,
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
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _ChatConversationCard(
                              item: item,
                              onTap: () =>
                                  onOpenConversation(item.conversationId),
                              onLongPress: () => onConversationLongPress(
                                item,
                                availableLists,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomClearance),
        child: FloatingActionButton(
          onPressed: onCreate,
          tooltip: 'New chat',
          child: const Icon(Icons.chat_bubble_outline),
        ),
      ),
    );
  }
}


class _ChatFilterBar extends StatelessWidget {
  const _ChatFilterBar({
    required this.selectedFilter,
    required this.selectedList,
    required this.availableLists,
    required this.onFilterChanged,
    required this.onListChanged,
    required this.onCreateList,
  });

  final ChatListFilter selectedFilter;
  final String? selectedList;
  final List<String> availableLists;
  final ValueChanged<ChatListFilter> onFilterChanged;
  final ValueChanged<String?> onListChanged;
  final VoidCallback onCreateList;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderColor),
          boxShadow: [
            BoxShadow(
              color: palette.shadowColor,
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick filters',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.primaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              _buildResponsiveFilterRow(
                isSmallScreen: isSmallScreen,
                children: [
                  _FloatingFilterPill(
                    label: 'All',
                    selected: selectedFilter == ChatListFilter.all,
                    onTap: () => onFilterChanged(ChatListFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FloatingFilterPill(
                    label: 'Unread',
                    selected: selectedFilter == ChatListFilter.unread,
                    onTap: () => onFilterChanged(ChatListFilter.unread),
                  ),
                  const SizedBox(width: 8),
                  _FloatingFilterPill(
                    label: 'Favorites',
                    selected: selectedFilter == ChatListFilter.favorites,
                    onTap: () => onFilterChanged(ChatListFilter.favorites),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lists',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.secondaryTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FloatingIconPill(
                    icon: Icons.add,
                    onTap: onCreateList,
                    tooltip: 'Create list',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildResponsiveListsRow(
                isSmallScreen: isSmallScreen,
                selectedList: selectedList,
                availableLists: availableLists,
                onListChanged: onListChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveFilterRow({
    required bool isSmallScreen,
    required List<Widget> children,
  }) {
    if (isSmallScreen) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: children,
      ),
    );
  }

  Widget _buildResponsiveListsRow({
    required bool isSmallScreen,
    required String? selectedList,
    required List<String> availableLists,
    required ValueChanged<String?> onListChanged,
  }) {
    final listPills = [
      _FloatingFilterPill(
        label: 'All lists',
        selected: selectedList == null,
        onTap: () => onListChanged(null),
      ),
      const SizedBox(width: 8),
      for (final list in availableLists) ...[
        _FloatingFilterPill(
          label: list,
          selected: list.toLowerCase() == selectedList?.toLowerCase(),
          onTap: () => onListChanged(
            list.toLowerCase() == selectedList?.toLowerCase() ? null : list,
          ),
        ),
        const SizedBox(width: 8),
      ],
    ];

    if (isSmallScreen) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: listPills.where((w) => w is! SizedBox).toList(),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: listPills,
      ),
    );
  }
}

class _ChatConversationCard extends StatelessWidget {
  const _ChatConversationCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatDiscoveryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.borderColor),
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: palette.avatarBackgroundColor,
                  foregroundColor: Colors.white,
                  child: Text(
                    item.title[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: palette.primaryTextColor,
                                  ),
                            ),
                          ),
                          if (item.trailing.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Text(
                              item.trailing,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: palette.secondaryTextColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.secondaryTextColor,
                        ),
                      ),
                      if (item.lists.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final list in item.lists)
                              _MiniListBadge(label: list),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ConversationStateColumn(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationStateColumn extends StatelessWidget {
  const _ConversationStateColumn({required this.item});

  final ChatDiscoveryItem item;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    final children = <Widget>[
      if (item.isFavorite)
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF7B500)),
      if (item.isPinned)
        Icon(Icons.push_pin, size: 16, color: palette.secondaryTextColor),
      if (item.unreadCount > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: palette.accentColor,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: palette.accentColor.withAlpha(70),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            item.unreadCount > 99 ? '99+' : '${item.unreadCount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ];

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MiniListBadge extends StatelessWidget {
  const _MiniListBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.pillColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderColor),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.primaryTextColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FloatingFilterPill extends StatelessWidget {
  const _FloatingFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? palette.accentColor : palette.pillColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : palette.borderColor,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.accentColor.withAlpha(78),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : palette.primaryTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingIconPill extends StatelessWidget {
  const _FloatingIconPill({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.pillColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.borderColor),
            ),
            child: Icon(icon, color: palette.primaryTextColor, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveActionSheet extends StatelessWidget {
  const _ResponsiveActionSheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Extra padding so the floating nav never covers the sheet actions.
    final totalBottomPadding = max(80.0, bottomPadding + 80.0);
    
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: totalBottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _AddToListSheet extends StatefulWidget {
  const _AddToListSheet({
    required this.conversationTitle,
    required this.selectedLists,
    required this.availableLists,
  });

  final String conversationTitle;
  final List<String> selectedLists;
  final List<String> availableLists;

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  late List<String> _availableLists;
  late Set<String> _selectedLists;

  @override
  void initState() {
    super.initState();
    _availableLists = _normalizeListNames([
      ...widget.availableLists,
      ...widget.selectedLists,
    ]);
    _selectedLists = widget.selectedLists.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _FloatingChatsPalette.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.78;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add "${widget.conversationTitle}" to list',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.primaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose one or more lists you already created from the + button above.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: _availableLists.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.pillColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'No lists yet. Create a list first from the + button above the chats.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.secondaryTextColor,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final list in _availableLists)
                            FilterChip(
                              label: Text(list),
                              selected: _selectedLists.any(
                                (selected) =>
                                    selected.toLowerCase() ==
                                    list.toLowerCase(),
                              ),
                              onSelected: (_) => _toggleList(list),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(const <String>[]),
                  child: const Text('Clear all'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_normalizeListNames(_selectedLists)),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleList(String list) {
    setState(() {
      final existing = _selectedLists.cast<String?>().firstWhere(
        (value) => value?.toLowerCase() == list.toLowerCase(),
        orElse: () => null,
      );
      if (existing != null) {
        _selectedLists.remove(existing);
      } else {
        _selectedLists.add(list);
      }
    });
  }
}

class _FloatingChatsPalette {
  const _FloatingChatsPalette({
    required this.surfaceColor,
    required this.cardColor,
    required this.pillColor,
    required this.borderColor,
    required this.shadowColor,
    required this.accentColor,
    required this.avatarBackgroundColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  final Color surfaceColor;
  final Color cardColor;
  final Color pillColor;
  final Color borderColor;
  final Color shadowColor;
  final Color accentColor;
  final Color avatarBackgroundColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  factory _FloatingChatsPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _FloatingChatsPalette(
      surfaceColor: isDark ? const Color(0xFF16273A) : Colors.white,
      cardColor: isDark ? const Color(0xFF18293D) : Colors.white,
      pillColor: isDark
          ? Colors.white.withAlpha(14)
          : theme.colorScheme.primary.withAlpha(10),
      borderColor: Colors.white.withAlpha(isDark ? 20 : 10),
      shadowColor: Colors.black.withAlpha(isDark ? 110 : 26),
      accentColor: isDark ? const Color(0xFF2395FF) : theme.colorScheme.primary,
      avatarBackgroundColor: isDark
          ? const Color(0xFF2395FF)
          : const Color(0xFF203347),
      primaryTextColor: isDark ? Colors.white : const Color(0xFF1B2D41),
      secondaryTextColor: isDark
          ? Colors.white.withAlpha(178)
          : const Color(0xFF5B6B7B),
    );
  }
}

List<String> _normalizeListNames(Iterable<String> values) {
  final deduped = <String, String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    deduped.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  return deduped.values.toList(growable: false);
}

String? _normalizeSingleListName(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = _normalizeListNames([value]);
  if (normalized.isEmpty) {
    return null;
  }
  return normalized.first;
}

enum _ConversationDeleteScope { forMe, forEveryone }
