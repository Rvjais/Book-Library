import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../common/app_sheet.dart';
import '../../../reader/engines/reader_engine.dart';

Future<int?> showSearchSheet(
  BuildContext context, {
  required ReaderEngine engine,
  required bool enabled,
}) {
  return showAppSheet<int>(
    context: context,
    builder: (_) => _SearchSheet(engine: engine, enabled: enabled),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.engine, required this.enabled});

  final ReaderEngine engine;
  final bool enabled;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _controller = TextEditingController();

  List<ReaderSearchHit> _results = const <ReaderSearchHit>[];
  bool _searching = false;
  String _query = '';
  bool _searched = false;
  int _token = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? value]) async {
    final query = (value ?? _controller.text).trim();
    if (!widget.enabled) return;
    final token = ++_token;
    if (query.length < 2) {
      setState(() {
        _results = const <ReaderSearchHit>[];
        _searching = false;
        _searched = false;
        _query = query;
      });
      return;
    }
    setState(() {
      _searching = true;
      _query = query;
    });
    try {
      final hits = await widget.engine.search(query);
      if (!mounted || token != _token) return;
      setState(() {
        _results = hits;
        _searching = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _results = const <ReaderSearchHit>[];
        _searching = false;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: 'Search in book',
          subtitle: widget.enabled
              ? 'Find a word or phrase across every page.'
              : 'Text search is only available for EPUB books.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            controller: _controller,
            autofocus: widget.enabled,
            enabled: widget.enabled,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (value) {
              _debounce?.cancel();
              if (value.trim().length < 2) {
                _search(value);
                return;
              }
              // Searching lowercases every chapter; wait for a pause in typing.
              _debounce = Timer(
                const Duration(milliseconds: 260),
                () => _search(value),
              );
            },
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Search this book',
            ),
          ),
        ),
        Flexible(
          child: _buildResults(theme),
        ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (!widget.enabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 44),
        child: Text(
          'PDF pages are images, so they cannot be searched locally. '
          'EPUB books can be searched instantly.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 46),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (!_searched) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 44),
        child: Text(
          'Type at least two letters to search.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 44),
        child: Text(
          'No matches for “$_query”.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outline.withValues(alpha: 0.18),
      ),
      itemBuilder: (context, index) {
        final hit = _results[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          title: Text(
            hit.chapter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: theme.colorScheme.primary,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: _HighlightedText(
              text: hit.snippet,
              query: _query,
              dimColor: theme.colorScheme.onSurfaceVariant,
              highlightColor: theme.colorScheme.primary,
            ),
          ),
          trailing: Text(
            'p. ${hit.pageIndex + 1}',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => Navigator.of(context).pop(hit.pageIndex),
        );
      },
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.dimColor,
    required this.highlightColor,
  });

  final String text;
  final String query;
  final Color dimColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    var start = 0;
    while (needle.isNotEmpty) {
      final index = lower.indexOf(needle, start);
      if (index < 0) break;
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + needle.length),
          style: TextStyle(
            color: highlightColor,
            fontWeight: FontWeight.w600,
            backgroundColor: fade(highlightColor, 0.12),
          ),
        ),
      );
      start = index + needle.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: dimColor,
          fontFamily: kSerif,
          fontFamilyFallback: kSerifFallback,
        ),
        children: spans,
      ),
    );
  }
}
