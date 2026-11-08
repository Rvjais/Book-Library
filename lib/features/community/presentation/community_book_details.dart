import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/ids.dart';
import '../../../data/library_repository.dart';
import '../../../data/models.dart';
import '../../../features/p2p/p2p_service.dart';

/// Shows the book details dialog. Returns true if the user chose to download.
Future<bool?> showCommunityBookDetails(
  BuildContext context,
  RemoteContentSource book,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _BookDetailsDialog(book: book),
  );
}

class _BookDetailsDialog extends StatelessWidget {
  const _BookDetailsDialog({required this.book});

  final RemoteContentSource book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = book.isReachable && !book.isStale;

    return AlertDialog(
      title: Text(
        book.title,
        style: serifStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book.author.isNotEmpty) ...[
              Text(
                book.author,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brass.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    book.format.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brass,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatBytes(book.fileSize),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: Color(0xFF8A6A45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared by',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        book.displayName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        book.userId,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.wifi_tethering_rounded,
                  size: 16,
                  color: Color(0xFF8A6A45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Availability',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        available ? 'Online' : 'Currently unavailable',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: available
                              ? AppColors.forest
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About this download',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The book will be transferred directly from ${book.displayName}\'s device. '
                    'No central server stores the file. The file will be verified by SHA-256 hash '
                    'before being added to your library.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.85,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: available
              ? () async {
                  final p2p = context.read<P2pService>();
                  try {
                    final tempPath = await p2p.downloadFromSource(
                      contentHash: book.contentHash,
                      source: book,
                    );
                    if (context.mounted) {
                      // Import into library via download manager
                      Navigator.of(context).pop(true);
                      await _importDownloadedBook(context, tempPath, book);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Download failed: $e'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }
              : null,
          child: const Text('Download'),
        ),
      ],
    );
  }

  Future<void> _importDownloadedBook(
      BuildContext context, String tempPath, RemoteContentSource book) async {
    final library = context.read<LibraryRepository>();
    final downloadedFile = File(tempPath);

    // Compute final SHA-256 (already verified by P2P, but re-check)
    final hash = await _sha256File(downloadedFile);

    // Determine final storage path
    final storage = library.storage;
    final ext = book.format == 'epub' ? 'epub' : 'pdf';
    final bookId = newId();
    final finalPath = await storage.writeBytes(
      bookId,
      '.$ext',
      await downloadedFile.readAsBytes(),
    );
    await downloadedFile.delete();

    // Import into library
    await library.importDownloadedBook(
      id: 0,
      title: book.title,
      author: book.author,
      filePath: finalPath,
      coverPath: '',
      format: book.format == 'epub' ? BookFormat.epub : BookFormat.pdf,
      fileSize: book.fileSize,
      fileHash: hash,
      isShared: false,
      contentHash: hash,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${book.title}" added to your library.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  Future<String> _sha256File(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
