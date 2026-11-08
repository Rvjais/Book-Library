import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'data/settings_repository.dart';
import 'features/identity/data/peer_identity.dart';
import 'features/home/home_shell.dart';

class LibReadyApp extends StatelessWidget {
  const LibReadyApp({super.key, required this.identity});

  final IdentityRepository identity;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>();
    return MaterialApp(
      title: 'LibReady',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeShell(identity: identity),
    );
  }
}
