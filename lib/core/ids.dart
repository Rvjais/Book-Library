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

/// Hashes the length plus 256 KiB sampled from the start, middle and end of a
/// file. Sampling the middle matters: two books of identical size with similar
/// headers and footers (common for scanned PDFs) used to collide.
Future<String> fileFingerprint(File file) async {
  const chunkSize = 256 * 1024;
  final length = await file.length();
  final handle = await file.open();
  try {
    final head = await handle.read(min(chunkSize, length));
    Uint8List middle = Uint8List(0);
    if (length > chunkSize * 2) {
      await handle.setPosition(length ~/ 2 - chunkSize ~/ 2);
      middle = await handle.read(chunkSize);
    }
    Uint8List tail = Uint8List(0);
    if (length > chunkSize) {
      await handle.setPosition(max(0, length - chunkSize));
      tail = await handle.read(chunkSize);
    }
    final builder = BytesBuilder(copy: false)
      ..add('$length|'.codeUnits)
      ..add(head)
      ..add(middle)
      ..add(tail);
    return sha1.convert(builder.takeBytes()).toString();
  } finally {
    await handle.close();
  }
}

/// Full-file SHA-256 hash. Used as the stable content identifier for P2P
/// sharing — identical content always produces the same hash regardless of
/// file name or metadata.
Future<String> sha256File(File file) async {
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
}
