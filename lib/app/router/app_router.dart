import 'package:chatify/features/auth/presentation/pages/auth_page.dart';
import 'package:chatify/features/backup/presentation/pages/backup_page.dart';
import 'package:chatify/features/business/presentation/pages/whatsapp_business_page.dart';
import 'package:chatify/features/calls/presentation/pages/calls_page.dart';
import 'package:chatify/features/chats/presentation/pages/chat_list_page.dart';
import 'package:chatify/features/chats/presentation/pages/chat_page.dart';
import 'package:chatify/features/linked_devices/presentation/pages/linked_devices_page.dart';
import 'package:chatify/features/profile/presentation/pages/user_profile_page.dart';
import 'package:chatify/features/search/presentation/pages/search_page.dart';
import 'package:chatify/features/settings/presentation/pages/settings_page.dart';
import 'package:chatify/features/status/presentation/pages/status_page.dart';
import 'package:chatify/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/auth',
    routes: [
      GoRoute(path: '/auth', builder: (context, state) => const AuthPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/chats',
                builder: (context, state) => const ChatListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/status',
                builder: (context, state) => const StatusPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/calls',
                builder: (context, state) => const CallsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            ChatPage(conversationId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/business/whatsapp',
        builder: (context, state) => const WhatsAppBusinessPage(),
      ),
      GoRoute(
        path: '/profile/:uid',
        builder: (context, state) =>
            UserProfilePage(userId: state.pathParameters['uid'] ?? ''),
      ),
      GoRoute(
        path: '/linked-devices',
        builder: (context, state) => const LinkedDevicesPage(),
      ),
      GoRoute(path: '/backup', builder: (context, state) => const BackupPage()),
    ],
  );
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: l10n.chats,
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: l10n.status,
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: l10n.calls,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: l10n.settings,
          ),
        ],
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
