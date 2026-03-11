import 'dart:async';
import 'dart:collection';

import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/core/notifications/in_app_notification_center.dart';
import 'package:flutter/material.dart';

class InAppNotificationHost extends StatefulWidget {
  InAppNotificationHost({
    required this.child,
    InAppNotificationCenter? notificationCenter,
    this.displayDuration = const Duration(seconds: 4),
    this.onNotificationTap,
    super.key,
  }) : notificationCenter =
           notificationCenter ?? InAppNotificationCenter.instance;

  final Widget child;
  final InAppNotificationCenter notificationCenter;
  final Duration displayDuration;
  final Future<void> Function(InAppMessageNotification notification)?
  onNotificationTap;

  @override
  State<InAppNotificationHost> createState() => _InAppNotificationHostState();
}

class _InAppNotificationHostState extends State<InAppNotificationHost> {
  static const Duration _hideAnimationDuration = Duration(milliseconds: 260);

  final Queue<InAppMessageNotification> _queue =
      Queue<InAppMessageNotification>();
  StreamSubscription<InAppMessageNotification>? _subscription;
  Timer? _displayTimer;
  Timer? _hideTimer;
  InAppMessageNotification? _activeNotification;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.notificationCenter.stream.listen((notification) {
      _queue.add(notification);
      if (_activeNotification == null) {
        _showNext();
      }
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    _hideTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_activeNotification != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: AnimatedSlide(
              duration: _hideAnimationDuration,
              curve: Curves.easeOutCubic,
              offset: _visible ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: _hideAnimationDuration,
                curve: Curves.easeOut,
                opacity: _visible ? 1 : 0,
                child: _NotificationPopup(
                  notification: _activeNotification!,
                  onTap: _handleNotificationTap,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showNext() {
    if (!mounted || _activeNotification != null || _queue.isEmpty) {
      return;
    }

    _displayTimer?.cancel();
    _hideTimer?.cancel();

    setState(() {
      _activeNotification = _queue.removeFirst();
      _visible = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeNotification == null) {
        return;
      }
      setState(() => _visible = true);
      _displayTimer = Timer(widget.displayDuration, _dismissActive);
    });
  }

  Future<void> _handleNotificationTap() async {
    final active = _activeNotification;
    if (active == null) {
      return;
    }

    if (widget.onNotificationTap != null) {
      await widget.onNotificationTap!(active);
    } else {
      AppRouter.router.push(
        '/chat/${Uri.encodeComponent(active.conversationId)}',
      );
    }
    _dismissActive();
  }

  void _dismissActive() {
    if (!mounted || _activeNotification == null) {
      return;
    }

    _displayTimer?.cancel();
    _hideTimer?.cancel();

    setState(() => _visible = false);
    _hideTimer = Timer(_hideAnimationDuration, () {
      if (!mounted) {
        return;
      }
      setState(() => _activeNotification = null);
      _showNext();
    });
  }
}

class _NotificationPopup extends StatelessWidget {
  const _NotificationPopup({required this.notification, required this.onTap});

  final InAppMessageNotification notification;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.mark_chat_unread_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
