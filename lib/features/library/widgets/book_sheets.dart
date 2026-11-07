import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/formatting.dart';
import '../../../data/library_repository.dart';
import '../../../data/models.dart';
import '../../../epub/epub_models.dart';
import '../../../epub/epub_parser.dart';
import '../../common/app_sheet.dart';
import 'book_cover_view.dart';

enum BookAction { open, readAgain }

Future<BookAction?> showBookActionsSheet(BuildContext context, Book book) {
  return showAppSheet<BookAction>(
    context: context,
    builder: (_) => _BookSheet(book: book),
  );
}

class _BookSheet extends StatefulWidget {
  const _BookSheet({required this.book});

  final Book book;

  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  late Book _book;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
  }

  LibraryRepository get _repo => context.read<LibraryRepository>();

  Future<void> _toggleFavorite() async {
    final next = !_book.isFavorite;
    await _repo.setFavorite(_book, next);
    if (!mounted) return;
    setState(() => _book = _book.copyWith(isFavorite: next));
  }

  Future<void> _toggleFinished() async {
    final next = !_book.isFinished;
    await _repo.setFinished(_book, next);
    if (!mounted) return;
    setState(() =>
        _book = _repo.bookById(_book.id) ?? _book.copyWith(isFinished: next));
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _book.title);
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit book title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nextTitle == null || nextTitle.isEmpty || !mounted) return;

    await _repo.updateMetadata(_book, title: nextTitle);
    if (!mounted) return;
    setState(() => _book = _repo.bookById(_book.id) ?? _book.copyWith(title: nextTitle));
    showToast(context, 'Title updated.');
  }

  Future<void> _changeCoverFromGallery() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: 'Choose cover from gallery',
        type: FileType.image,
      );
    } catch (_) {
      if (mounted) showToast(context, 'The image picker could not be opened.');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busy = 'Saving cover…');
    try {
      final bytes = await picked.readAsBytes();
      final ok = await _repo.setCoverFromBytes(_book, bytes);
      if (!mounted) return;
      if (ok) {
        setState(() => _book = _repo.bookById(_book.id) ?? _book);
      }
      showToast(
          context, ok ? 'Cover updated.' : 'That image could not be used.');
    } catch (_) {
      if (mounted) showToast(context, 'That image could not be used.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _chooseCoverFromBookPages() async {
    if (_book.isPdf) {
      await _pickPdfPageCover();
    } else {
      await _pickEpubImageCover();
    }
  }

  Future<void> _pickPdfPageCover() async {
    final totalPages = _book.pageCount;
    if (totalPages <= 0) {
      showToast(context, 'Could not read pages from this PDF.');
      return;
    }

    final pageNumber = await showDialog<int>(
      context: context,
      builder: (ctx) => _PickPdfPageDialog(
        filePath: _book.filePath,
        totalPages: totalPages,
      ),
    );

    if (pageNumber == null || !mounted) return;

    setState(() => _busy = 'Rendering page $pageNumber as cover…');
    try {
      final doc = await PdfDocument.openFile(_book.filePath);
      Uint8List? renderedBytes;
      try {
        final page = await doc.getPage(pageNumber);
        try {
          final ratio = page.width <= 0 ? 1.5 : page.height / page.width;
          final rendered = await page.render(
            width: 900,
            height: 900 * ratio,
            format: PdfPageImageFormat.jpeg,
            quality: 88,
          );
          renderedBytes = rendered?.bytes;
        } finally {
          await page.close();
        }
      } finally {
        await doc.close();
      }

      if (renderedBytes != null) {
        final ok = await _repo.setCoverFromBytes(_book, renderedBytes);
        if (!mounted) return;
        if (ok) {
          setState(() => _book = _repo.bookById(_book.id) ?? _book);
        }
        showToast(context, ok ? 'Cover set from page $pageNumber.' : 'Could not save cover.');
      }
    } catch (e) {
      if (mounted) showToast(context, 'Error rendering page: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickEpubImageCover() async {
    setState(() => _busy = 'Loading images from book…');
    List<Uint8List> images = [];
    try {
      final epub = await EpubParser.open(_book.filePath);
      // Collect coverBytes + all images from chapters
      if (epub.coverBytes != null && epub.coverBytes!.isNotEmpty) {
        images.add(epub.coverBytes!);
      }
      for (final ch in epub.chapters) {
        for (final block in ch.blocks) {
          if (block is RawImageBlock && block.bytes.isNotEmpty) {
            images.add(block.bytes);
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading EPUB images: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }

    if (!mounted) return;
    if (images.isEmpty) {
      showToast(context, 'No images found inside this EPUB.');
      return;
    }

    final selectedBytes = await showDialog<Uint8List>(
      context: context,
      builder: (ctx) => _PickEpubImageDialog(images: images),
    );

    if (selectedBytes == null || !mounted) return;

    setState(() => _busy = 'Saving cover…');
    try {
      final ok = await _repo.setCoverFromBytes(_book, selectedBytes);
      if (!mounted) return;
      if (ok) {
        setState(() => _book = _repo.bookById(_book.id) ?? _book);
      }
      showToast(context, ok ? 'Cover updated.' : 'Could not save cover.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _rebuildCover() async {
    setState(() => _busy = 'Rebuilding cover…');
    try {
      final ok = await _repo.regenerateCover(_book);
      if (!mounted) return;
      if (ok) {
        setState(() => _book = _repo.bookById(_book.id) ?? _book);
      }
      showToast(
        context,
        ok
            ? 'Cover rebuilt from the book.'
            : 'No cover could be found in this file.',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this book?',
      message: '“${_book.title}” and its saved cover will be deleted from this '
          'device. This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _repo.deleteBook(_book);
    if (!mounted) return;
    navigator.pop();
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${_book.title}” removed.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        ),
      );
  }

  void _showDetails() {
    showDialog<void>(
      context: context,
      builder: (_) => _BookDetailsDialog(book: _book),
    );
  }

  void _open() => Navigator.of(context).pop(
        _book.isFinished ? BookAction.readAgain : BookAction.open,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = _book.hasStarted && !_book.isFinished;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCoverView(book: _book, width: 66, height: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: serifStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                              height: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit title',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: _editTitle,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _book.author.isEmpty ? 'Unknown author' : _book.author,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatLine(),
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.3,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (_busy != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(_busy!, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (started) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _book.progress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor:
                    theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatPercent(_book.progress)} read · page '
              '${_book.readingPosition.page + 1} of ${_book.pageCount}',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 2),
          FilledButton.icon(
            onPressed: _open,
            icon: Icon(
              _book.isFinished
                  ? Icons.replay_rounded
                  : started
                      ? Icons.auto_stories_rounded
                      : Icons.menu_book_rounded,
            ),
            label: Text(
              _book.isFinished
                  ? 'Read again'
                  : started
                      ? 'Continue reading'
                      : 'Start reading',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          _SheetAction(
            icon: Icons.edit_note_rounded,
            title: 'Rename book title',
            onTap: _editTitle,
          ),
          _SheetAction(
            icon: _book.isFavorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            iconColor: AppColors.brass,
            title: _book.isFavorite ? 'In favourites' : 'Add to favourites',
            onTap: _toggleFavorite,
          ),
          _SheetAction(
            icon: _book.isFinished
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded,
            iconColor: _book.isFinished
                ? AppColors.forest
                : theme.colorScheme.onSurfaceVariant,
            title: _book.isFinished ? 'Mark as unread' : 'Mark as finished',
            onTap: _toggleFinished,
          ),
          const Divider(height: 18),
          _SheetAction(
            icon: Icons.auto_stories_outlined,
            title: _book.isPdf
                ? 'Choose cover from any page of book'
                : 'Choose cover from book pages / illustrations',
            onTap: _busy == null ? _chooseCoverFromBookPages : null,
          ),
          _SheetAction(
            icon: Icons.photo_library_outlined,
            title: 'Choose cover from gallery',
            onTap: _busy == null ? _changeCoverFromGallery : null,
          ),
          _SheetAction(
            icon: Icons.auto_fix_high_rounded,
            title: 'Rebuild original cover from file',
            onTap: _busy == null ? _rebuildCover : null,
          ),
          const Divider(height: 18),
          _SheetAction(
            icon: Icons.info_outline_rounded,
            title: 'Book details',
            onTap: _showDetails,
          ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            iconColor: theme.colorScheme.error,
            title: 'Remove from library',
            titleColor: theme.colorScheme.error,
            onTap: _delete,
          ),
        ],
      ),
    );
  }

  String _formatLine() {
    final parts = <String>[_book.format.label];
    if (_book.pageCount > 0) {
      parts.add('${_book.pageCount} pages');
    }
    parts.add(formatBytes(_book.fileSize));
    return parts.join('  ·  ');
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = onTap == null
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -1),
      leading: Icon(icon, size: 21, color: iconColor ?? foreground),
      title: Text(
        title,
        style: TextStyle(fontSize: 14, color: titleColor ?? foreground),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      onTap: onTap,
    );
  }
}

/// Dialog for browsing and selecting any page from a PDF book
class _PickPdfPageDialog extends StatefulWidget {
  const _PickPdfPageDialog({
    required this.filePath,
    required this.totalPages,
  });

  final String filePath;
  final int totalPages;

  @override
  State<_PickPdfPageDialog> createState() => _PickPdfPageDialogState();
}

class _PickPdfPageDialogState extends State<_PickPdfPageDialog> {
  int _selectedPage = 1;
  final TextEditingController _pageInput = TextEditingController(text: '1');
  PdfDocument? _doc;
  Uint8List? _previewBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  Future<void> _loadPage(int pageNum) async {
    setState(() => _loading = true);
    try {
      _doc ??= await PdfDocument.openFile(widget.filePath);
      final p = await _doc!.getPage(pageNum);
      try {
        final ratio = p.width <= 0 ? 1.5 : p.height / p.width;
        final res = await p.render(
          width: 320,
          height: 320 * ratio,
          format: PdfPageImageFormat.jpeg,
          quality: 75,
        );
        if (mounted) {
          setState(() {
            _selectedPage = pageNum;
            _previewBytes = res?.bytes;
            _loading = false;
          });
        }
      } finally {
        await p.close();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _doc?.close();
    _pageInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Cover Page'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1 / 1.45,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _previewBytes != null
                        ? Image.memory(_previewBytes!, fit: BoxFit.contain)
                        : const Center(child: Text('Unable to preview page')),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _selectedPage > 1
                      ? () {
                          final prev = _selectedPage - 1;
                          _pageInput.text = '$prev';
                          _loadPage(prev);
                        }
                      : null,
                ),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _pageInput,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (val) {
                      final n = int.tryParse(val);
                      if (n != null && n >= 1 && n <= widget.totalPages) {
                        _loadPage(n);
                      } else {
                        _pageInput.text = '$_selectedPage';
                      }
                    },
                  ),
                ),
                Text(' / ${widget.totalPages}'),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _selectedPage < widget.totalPages
                      ? () {
                          final next = _selectedPage + 1;
                          _pageInput.text = '$next';
                          _loadPage(next);
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedPage),
          child: const Text('Set as Cover'),
        ),
      ],
    );
  }
}

/// Dialog for selecting cover from images inside an EPUB
class _PickEpubImageDialog extends StatelessWidget {
  const _PickEpubImageDialog({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Cover Artwork'),
      content: SizedBox(
        width: 340,
        height: 380,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1 / 1.45,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final imgBytes = images[index];
            return InkWell(
              onTap: () => Navigator.of(context).pop(imgBytes),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black26),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  imgBytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _BookDetailsDialog extends StatelessWidget {
  const _BookDetailsDialog({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = book.filePath.split(RegExp(r'[\\/]')).last;
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
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: BookCoverView(book: book, width: 96, height: 140),
              ),
              const SizedBox(height: 18),
              _DetailRow(
                  label: 'Author',
                  value: book.author.isEmpty ? 'Unknown' : book.author),
              _DetailRow(label: 'Format', value: book.format.label),
              _DetailRow(label: 'File', value: fileName),
              _DetailRow(label: 'Size', value: formatBytes(book.fileSize)),
              _DetailRow(
                  label: 'Pages',
                  value: book.pageCount > 0 ? '${book.pageCount}' : '—'),
              _DetailRow(label: 'Added', value: formatShortDate(book.addedAt)),
              _DetailRow(
                label: 'Last opened',
                value: book.lastOpenedAt > 0
                    ? formatShortDate(book.lastOpenedAt)
                    : 'Not read yet',
              ),
              _DetailRow(
                  label: 'Progress', value: formatPercent(book.progress)),
              const SizedBox(height: 12),
              Text(
                'About this book',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                (book.description ?? '').trim().isEmpty
                    ? 'No description was included in the file.'
                    : book.description!.trim(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
