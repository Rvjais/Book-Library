import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/library_repository.dart';
import 'data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await SettingsRepository.load();
  final library = LibraryRepository(settings: settings);
  await library.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: settings),
        ChangeNotifierProvider<LibraryRepository>.value(value: library),
      ],
      child: const LibReadyApp(),
    ),
  );
}
