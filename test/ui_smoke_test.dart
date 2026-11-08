import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:libready/core/app_theme.dart';
import 'package:libready/data/library_repository.dart';
import 'package:libready/data/models.dart';
import 'package:libready/data/settings_repository.dart';
import 'package:libready/features/identity/data/peer_identity.dart';
import 'package:libready/features/library/library_screen.dart';
import 'package:libready/features/library/widgets/shelf_row.dart';
import 'package:libready/features/reading/reading_screen.dart';
import 'package:libready/features/settings/settings_screen.dart';

class _FakeLibrary extends LibraryRepository {
  _FakeLibrary({required super.settings, required this.fakeBooks});

  final List<Book> fakeBooks;

  @override
  bool get isLoading => false;

  @override
  Object? get lastError => null;

  @override
  List<Book> get books => fakeBooks;

  @override
  List<Book> get visibleBooks => fakeBooks;

  @override
  int get bookCount => fakeBooks.length;

  @override
  int get readingCount =>
      fakeBooks.where((book) => book.hasStarted && !book.isFinished).length;

  @override
  int get finishedCount => fakeBooks.where((book) => book.isFinished).length;

  @override
  List<Book> get inProgress => fakeBooks
      .where((book) => book.hasStarted && !book.isFinished)
      .toList();

  @override
  Future<int> storageBytes() async => 0;
}

Book _book(
  int id,
  String title, {
  double progress = 0,
  bool favorite = false,
  bool finished = false,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Book(
    id: id,
    title: title,
    author: 'Author $id',
    filePath: '',
    coverPath: '',
    format: BookFormat.epub,
    fileSize: 1024 * 1024,
    fileHash: 'hash-$id',
    pageCount: 240,
    addedAt: now - id * 86400000,
    lastOpenedAt: progress > 0 ? now - id * 3600000 : 0,
    progress: progress,
    position: '{}',
    isFavorite: favorite,
    isFinished: finished,
    isShared: false,
    contentHash: 'hash-$id',
  );
}

Widget _wrap(
  LibraryRepository library,
  SettingsRepository settings,
  IdentityRepository identity,
  Widget child,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsRepository>.value(value: settings),
      ChangeNotifierProvider<LibraryRepository>.value(value: library),
      ChangeNotifierProvider<IdentityRepository>.value(value: identity),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await SettingsRepository.load();
  });

  testWidgets('library draws shelves with book covers', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = _FakeLibrary(
      settings: settings,
      fakeBooks: [
        _book(1, 'The Psychology of Money', progress: 0.42, favorite: true),
        _book(2, 'Deep Work', progress: 0.12),
        _book(3, 'Meditations'),
        _book(4, 'The Let Them Theory', finished: true),
        _book(5, 'Atomic Habits'),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    final identity = IdentityRepository(
      prefs,
      const PeerIdentity(
        peerId: 'test-peer-id',
        userId: 'LIB-TEST1234',
        displayName: 'TestReader_001',
        publicKeyPem: 'test-public-key',
        privateKeyPem: 'test-private-key',
        createdAt: 0,
      ),
      'test-private-key',
    );

    await tester.pumpWidget(_wrap(library, settings, identity, const LibraryScreen()));
    await tester.pump();

    expect(find.text('LibReady'), findsOneWidget);
    expect(find.textContaining('5 books'), findsOneWidget);
    expect(find.byType(ShelfRow), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading tab shows continue card and progress', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = _FakeLibrary(
      settings: settings,
      fakeBooks: [
        _book(1, 'The Psychology of Money', progress: 0.42),
        _book(2, 'Deep Work', progress: 0.12),
        _book(3, 'Meditations', finished: true),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    final identity = IdentityRepository(
      prefs,
      const PeerIdentity(
        peerId: 'test-peer-id',
        userId: 'LIB-TEST1234',
        displayName: 'TestReader_001',
        publicKeyPem: 'test-public-key',
        privateKeyPem: 'test-private-key',
        createdAt: 0,
      ),
      'test-private-key',
    );

    await tester.pumpWidget(
      _wrap(library, settings, identity, ReadingScreen(onBrowseLibrary: () {})),
    );
    await tester.pump();

    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('The Psychology of Money'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings tab renders reading controls', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = _FakeLibrary(
      settings: settings,
      fakeBooks: [_book(1, 'Deep Work', progress: 0.2)],
    );
    final prefs = await SharedPreferences.getInstance();
    final identity = IdentityRepository(
      prefs,
      const PeerIdentity(
        peerId: 'test-peer-id',
        userId: 'LIB-TEST1234',
        displayName: 'TestReader_001',
        publicKeyPem: 'test-public-key',
        privateKeyPem: 'test-private-key',
        createdAt: 0,
      ),
      'test-private-key',
    );

    await tester.pumpWidget(
      _wrap(library, settings, identity, const SettingsScreen()),
    );
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('READING SETTINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
