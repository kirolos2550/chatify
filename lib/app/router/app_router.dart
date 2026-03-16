import 'package:chatify/features/auth/presentation/pages/auth_page.dart';
import 'package:chatify/features/backup/presentation/pages/backup_page.dart';
import 'package:chatify/features/business/presentation/pages/whatsapp_business_page.dart';
import 'package:chatify/features/calls/presentation/pages/call_details_page.dart';
import 'package:chatify/features/calls/presentation/pages/calls_page.dart';
import 'package:chatify/features/chats/presentation/pages/chat_list_page.dart';
import 'package:chatify/features/chats/presentation/pages/chat_page.dart';
import 'package:chatify/features/linked_devices/presentation/pages/linked_devices_page.dart';
import 'package:chatify/features/profile/presentation/pages/user_profile_page.dart';
import 'package:chatify/features/search/presentation/pages/search_page.dart';
import 'package:chatify/features/settings/presentation/pages/settings_page.dart';
import 'package:chatify/features/status/presentation/pages/status_page.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/bottom_nav_visibility.dart';
import 'package:chatify/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRouter {
  static bool _routeTracingEnabled = false;
  static String? _lastKnownRoute;

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
        builder: (context, state) => UserProfilePage(
          userId: Uri.decodeComponent(state.pathParameters['uid'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/linked-devices',
        builder: (context, state) => const LinkedDevicesPage(),
      ),
      GoRoute(path: '/backup', builder: (context, state) => const BackupPage()),
      GoRoute(
        path: '/call/:id',
        builder: (context, state) => CallDetailsPage(
          callId: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
        ),
      ),
    ],
  );

  static void enableRouteTracing() {
    if (_routeTracingEnabled) {
      return;
    }
    _routeTracingEnabled = true;
    router.routerDelegate.addListener(_handleRouterChange);
    _handleRouterChange();
  }

  static void _handleRouterChange() {
    final currentRoute = router.state.uri.toString();
    if (_lastKnownRoute == null) {
      _lastKnownRoute = currentRoute;
      AppLogger.setCurrentRoute(currentRoute);
      AppLogger.breadcrumb(
        'route.initial',
        action: 'navigation',
        route: currentRoute,
      );
      return;
    }

    if (_lastKnownRoute == currentRoute) {
      return;
    }

    final from = _lastKnownRoute;
    _lastKnownRoute = currentRoute;
    AppLogger.setCurrentRoute(currentRoute);
    AppLogger.breadcrumb(
      'route.transition',
      action: 'navigation',
      route: currentRoute,
      metadata: <String, Object?>{'from': from, 'to': currentRoute},
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = <_FloatingNavItemData>[
      _FloatingNavItemData(
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        label: l10n.chats,
      ),
      _FloatingNavItemData(
        icon: Icons.auto_stories_outlined,
        selectedIcon: Icons.auto_stories_rounded,
        label: l10n.status,
      ),
      _FloatingNavItemData(
        icon: Icons.call_outlined,
        selectedIcon: Icons.call_rounded,
        label: l10n.calls,
      ),
      _FloatingNavItemData(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: l10n.settings,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: BottomNavVisibilityController.isVisible,
        builder: (context, isVisible, child) {
          if (!isVisible) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: child!,
          );
        },
        child: _FloatingBottomNavBar(
          currentIndex: navigationShell.currentIndex,
          items: items,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}

class _FloatingBottomNavBar extends StatelessWidget {
  const _FloatingBottomNavBar({
    required this.currentIndex,
    required this.items,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final List<_FloatingNavItemData> items;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF16273A)
        : const Color(0xFF203347);
    final borderColor = Colors.white.withAlpha(isDark ? 30 : 22);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 120 : 55),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++)
              Expanded(
                child: _FloatingBottomNavItem(
                  data: items[index],
                  selected: index == currentIndex,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBottomNavItem extends StatelessWidget {
  const _FloatingBottomNavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _FloatingNavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Colors.white;
    final inactiveColor = Colors.white.withAlpha(178);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFF2395FF)
                      : Colors.transparent,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF2395FF).withAlpha(90),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  selected ? data.selectedIcon : data.icon,
                  color: activeColor,
                  size: 21,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: selected ? activeColor : inactiveColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11.5,
                ),
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavItemData {
  const _FloatingNavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
