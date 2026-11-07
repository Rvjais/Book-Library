import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _random = Random.secure();

/// Short, unique, filesystem-safe id.
String newId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final noise = List.generate(
    3,
    (_) => _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return '$now$noise';
}

/// Hashes the length plus the first and last 128 KiB of a file. Fast even for
/// very large PDFs and good enough to spot the same book imported twice.
Future<String> fileFingerprint(File file) async {
  const chunkSize = 128 * 1024;
  final length = await file.length();
  final handle = await file.open();
  try {
    final head = await handle.read(chunkSize);
    Uint8List tail = Uint8List(0);
    if (length > chunkSize) {
      await handle.setPosition(max(0, length - chunkSize));
      tail = await handle.read(chunkSize);
    }
    final builder = BytesBuilder(copy: false)
      ..add('$length|'.codeUnits)
      ..add(head)
      ..add(tail);
    return sha1.convert(builder.takeBytes()).toString();
  } finally {
    await handle.close();
  }
}
