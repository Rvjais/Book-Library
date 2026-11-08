import 'package:libready/data/models.dart';
import 'package:libready/features/p2p/data/content_advertisement.dart';
import 'package:meta/meta.dart';

/// A book discovered in the Community Store.
///
/// Combines catalog metadata with live availability information.
@immutable
class CommunityBook {
  const CommunityBook({
    required this.advertisement,
    required this.sources,
    required this.lastSeen,
  });

  final ContentAdvertisement advertisement;
  final List<ContentSource> sources;
  final int lastSeen;

  String get contentHash => advertisement.contentHash;
  String get title => advertisement.title;
  String get author => advertisement.author;
  String get format => advertisement.format;
  int get fileSize => advertisement.fileSize;
  String? get coverHash => advertisement.coverHash;
  String get publisherPeerId => advertisement.publisherPeerId;
  String get publisherUserId => advertisement.publisherUserId;
  String get publisherDisplayName => advertisement.publisherDisplayName;

  int get activeSourceCount =>
      sources.where((s) => s.isReachable && !s.isStale).length;

  bool get isAvailable => activeSourceCount > 0;

  bool get isStale {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastSeen > 300000; // 5 minutes
  }

  CommunityBook copyWith({
    ContentAdvertisement? advertisement,
    List<ContentSource>? sources,
    int? lastSeen,
  }) {
    return CommunityBook(
      advertisement: advertisement ?? this.advertisement,
      sources: sources ?? this.sources,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

extension CommunityBookX on CommunityBook {
  Book toBook() {
    return Book(
      id: 0, // assigned when imported into library
      title: title,
      author: author,
      filePath: '',
      coverPath: '',
      format: format == 'epub' ? BookFormat.epub : BookFormat.pdf,
      fileSize: fileSize,
      fileHash: contentHash,
      isShared: false,
      contentHash: contentHash,
      pageCount: 0,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      lastOpenedAt: 0,
      progress: 0,
      position: '{}',
      isFavorite: false,
      isFinished: false,
    );
  }
}

/// Filters for the Community Store.
enum CommunityFilter { all, pdf, epub }

/// Sort options for the Community Store.
enum CommunitySort { recent, title, size, sources }
