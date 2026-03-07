import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  static const List<_SearchResultItem> _catalog = [
    _SearchResultItem(
      title: 'Alice',
      subtitle: 'Conversation',
      route: '/chat/c_demo_1',
    ),
    _SearchResultItem(
      title: 'Family',
      subtitle: 'Conversation',
      route: '/chat/c_demo_2',
    ),
    _SearchResultItem(
      title: 'Linked devices',
      subtitle: 'Settings',
      route: '/linked-devices',
    ),
    _SearchResultItem(
      title: 'Encrypted backup',
      subtitle: 'Settings',
      route: '/backup',
    ),
  ];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filterResults(_query);
    return _SearchScaffold(
      queryController: _queryController,
      onQueryChanged: (value) {
        if (!mounted) {
          return;
        }
        setState(() => _query = value);
      },
      results: results,
    );
  }

  List<_SearchResultItem> _filterResults(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _catalog;
    }
    return _catalog.where((item) {
      return item.title.toLowerCase().contains(normalized) ||
          item.subtitle.toLowerCase().contains(normalized);
    }).toList();
  }
}

class _SearchScaffold extends StatelessWidget {
  const _SearchScaffold({
    required this.queryController,
    required this.onQueryChanged,
    required this.results,
  });

  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final List<_SearchResultItem> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: queryController,
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search chats, messages, media',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 0),
                itemBuilder: (context, index) {
                  final item = results[index];
                  return ListTile(
                    title: Text(item.title),
                    subtitle: Text(item.subtitle),
                    onTap: () => context.push(item.route),
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

class _SearchResultItem {
  const _SearchResultItem({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;
}
