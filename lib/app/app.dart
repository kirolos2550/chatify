// app/app.dart
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/app/theme/app_theme.dart';
import 'package:chatify/app/theme/app_theme_controller.dart';
import 'package:chatify/core/notifications/in_app_notification_host.dart';
import 'package:chatify/l10n/app_localizations.dart';
import 'package:chatify/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class ChatifyApp extends StatelessWidget {
  const ChatifyApp({required this.flavor, super.key});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final localeController = AppLocaleController.instance;
    final themeController = AppThemeController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([localeController, themeController]),
      builder: (context, _) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
        debugShowCheckedModeBanner: !flavor.isProd,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeController.themeMode,
        locale: localeController.locale,
        localeResolutionCallback: localeResolution,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: AppRouter.router,
        builder: (context, child) =>
            InAppNotificationHost(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
