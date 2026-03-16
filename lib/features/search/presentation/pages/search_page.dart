import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:chatify/features/chats/presentation/bloc/chats_cubit.dart';
import 'package:chatify/features/chats/presentation/models/chat_discovery_item.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  bool get _hasWiredChats =>
      getIt.isRegistered<ChatsCubit>() &&
      getIt.isRegistered<ConversationRepository>() &&
      Firebase.apps.isNotEmpty;

  static const List<ChatDiscoveryItem> _demoItems = [
    ChatDiscoveryItem(
      title: 'Alice',
      subtitle: '+201001112223',
      conversationId: 'c_demo_1',
      trailing: '10:42',
    ),
    ChatDiscoveryItem(
      title: 'Family',
      subtitle: 'Group conversation',
      conversationId: 'c_demo_2',
      trailing: '09:15',
      lists: ['Family'],
    ),
  ];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasWiredChats) {
      return _SearchScaffold(
        queryController: _queryController,
        onQueryChanged: _updateQuery,
        results: filterChatDiscoveryItems(items: _demoItems, query: _query),
        loading: false,
        showDemoHint: true,
      );
    }

    return BlocProvider(
      create: (_) => getIt<ChatsCubit>(),
      child: BlocBuilder<ChatsCubit, ChatsState>(
        builder: (context, state) {
          final items = state.items
              .where((conversation) => !conversation.isArchived)
              .map(mapConversationToChatDiscoveryItem)
              .toList(growable: false);
          return _SearchScaffold(
            queryController: _queryController,
            onQueryChanged: _updateQuery,
            results: filterChatDiscoveryItems(items: items, query: _query),
            loading: state.loading,
            showDemoHint: false,
          );
        },
      ),
    );
  }

  void _updateQuery(String value) {
    if (!mounted) {
      return;
    }
    setState(() => _query = value);
  }
}

class _SearchScaffold extends StatelessWidget {
  const _SearchScaffold({
    required this.queryController,
    required this.onQueryChanged,
    required this.results,
    required this.loading,
    required this.showDemoHint,
  });

  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final List<ChatDiscoveryItem> results;
  final bool loading;
  final bool showDemoHint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search chats')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: queryController,
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search by name or mobile number',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            if (showDemoHint)
              const MaterialBanner(
                content: Text(
                  'Live conversations are unavailable right now, so demo results are shown.',
                ),
                actions: [SizedBox.shrink()],
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty
                  ? const Center(
                      child: Text(
                        'No chats match this search yet.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text(item.title[0])),
                          title: Text(item.title),
                          subtitle: Text(item.subtitle),
                          trailing: item.unreadCount > 0
                              ? CircleAvatar(
                                  radius: 11,
                                  child: Text(
                                    item.unreadCount > 99
                                        ? '99+'
                                        : '${item.unreadCount}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                )
                              : null,
                          onTap: () =>
                              context.push('/chat/${item.conversationId}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
