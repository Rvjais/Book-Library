import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_repository.dart';
import '../../data/models.dart';
import 'reader_screen.dart';

Future<void> openBook(BuildContext context, Book book) async {
  final repo = context.read<LibraryRepository>();
  await repo.touchOpened(book);
  if (!context.mounted) return;
  final fresh = repo.bookById(book.id) ?? book;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ReaderScreen(book: fresh)),
  );
}
