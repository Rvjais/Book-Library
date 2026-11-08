import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../features/p2p/p2p_service.dart';
import 'community_book_details.dart';

/// The Community Store: browse books shared by peers on any network.
class CommunityStoreScreen extends StatefulWidget {
  const CommunityStoreScreen({super.key});

  @override
  State<CommunityStoreScreen> createState() => _CommunityStoreScreenState();
}

class _CommunityStoreScreenState extends State<CommunityStoreScreen> {
  String _query = '';
  String? _formatFilter; // 'pdf', 'epub', or null for all

  @override
  void initState() {
    super.initState();
    // Trigger initial discovery
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final p2p = context.read<P2pService>();
    if (p2p.catalog.isEmpty) {
      // Discovery happens via signaling server; query is triggered per-book
    }
  }

  @override
  Widget build(BuildContext context) {
    final p2p = context.watch<P2pService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Store'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          Expanded(
            child: _buildBookList(context, p2p),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search books by title or author',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.12),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.brass.withValues(alpha: 0.8),
            ),
          ),
        ),
        style: const TextStyle(
          color: Color(0xFFF3E8D2),
          fontSize: 15,
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: FilterChip(
              label: const Text('All'),
              selected: _formatFilter == null,
              onSelected: (value) => setState(() => _formatFilter = null),
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              selectedColor: AppColors.brass,
              checkmarkColor: const Color(0xFF2A1B0C),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: const Text('PDF'),
              selected: _formatFilter == 'pdf',
              onSelected: (value) => setState(() => _formatFilter = 'pdf'),
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              selectedColor: AppColors.brass,
              checkmarkColor: const Color(0xFF2A1B0C),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: const Text('EPUB'),
              selected: _formatFilter == 'epub',
              onSelected: (value) => setState(() => _formatFilter = 'epub'),
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              selectedColor: AppColors.brass,
              checkmarkColor: const Color(0xFF2A1B0C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(BuildContext context, P2pService p2p) {
    final theme = Theme.of(context);
    var books = p2p.catalog.where((book) {
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return book.title.toLowerCase().contains(q) ||
            book.author.toLowerCase().contains(q);
      }
      if (_formatFilter != null && book.format != _formatFilter) return false;
      return true;
    }).toList();

    // Sort: available first, then by source count
    books.sort((a, b) {
      final aAvail = b.isReachable ? 1 : 0;
      final bAvail = a.isReachable ? 1 : 0;
      return bAvail.compareTo(aAvail);
    });

    if (books.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 60,
              color: Color(0xFF8A6A45),
            ),
            const SizedBox(height: 16),
            Text(
              'No books shared on the network',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask friends to run LibReady and share books. '
              'Books appear here when peers are online and sharing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return _CommunityBookTile(book: book);
      },
    );
  }
}

class _CommunityBookTile extends StatelessWidget {
  const _CommunityBookTile({required this.book});

  final RemoteContentSource book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = book.isReachable && !book.isStale;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: SizedBox(
          width: 52,
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(Icons.book_outlined, size: 28),
            ),
          ),
        ),
        title: Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              book.author.isNotEmpty ? book.author : 'Unknown author',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: available
                        ? AppColors.forest.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${book.format.toUpperCase()}  ·  ${formatBytes(book.fileSize)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: available
                          ? AppColors.forest
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  available
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_off_rounded,
                  size: 14,
                  color: available
                      ? AppColors.forest
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  available ? 'Online' : 'Unavailable',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: available
            ? IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () async {
                  final result = await showCommunityBookDetails(context, book);
                  if (result == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading "${book.title}"…'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              )
            : const Icon(
                Icons.schedule_rounded,
                size: 20,
                color: Color(0xFF8A6A45),
              ),
        onTap: () async {
          final result = await showCommunityBookDetails(context, book);
          if (result == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${book.title}"…'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
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
