import 'package:meta/meta.dart';

/// Data model for a book advertised by a peer on the network.
///
/// This is metadata only — the actual file bytes stay on the publishing
/// device and are transferred directly peer-to-peer when requested.
@immutable
class ContentAdvertisement {
  const ContentAdvertisement({
    required this.contentHash,
    required this.title,
    required this.author,
    required this.format,
    required this.fileSize,
    required this.coverHash,
    required this.publisherPeerId,
    required this.publisherUserId,
    required this.publisherDisplayName,
    required this.advertisedAt,
    required this.ttlSeconds,
  });

  /// SHA-256 hash of the file content — the stable content identifier.
  final String contentHash;

  final String title;
  final String author;
  final String format; // 'pdf' or 'epub'
  final int fileSize;

  /// SHA-256 of the cover image, if any. Used to verify cover integrity.
  final String? coverHash;

  /// Peer ID of the device advertising this content.
  final String publisherPeerId;

  /// Human-readable User ID of the publisher.
  final String publisherUserId;

  /// Display name of the publisher.
  final String publisherDisplayName;

  /// When this advertisement was created, milliseconds since epoch.
  final int advertisedAt;

  /// Time-to-live in seconds. After this, the advertisement is considered
  /// stale and should not be used for discovery.
  final int ttlSeconds;

  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > advertisedAt + ttlSeconds * 1000;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'contentHash': contentHash,
        'title': title,
        'author': author,
        'format': format,
        'fileSize': fileSize,
        'coverHash': coverHash,
        'publisherPeerId': publisherPeerId,
        'publisherUserId': publisherUserId,
        'publisherDisplayName': publisherDisplayName,
        'advertisedAt': advertisedAt,
        'ttlSeconds': ttlSeconds,
      };

  factory ContentAdvertisement.fromJson(Map<String, dynamic> json) {
    return ContentAdvertisement(
      contentHash: json['contentHash'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      format: json['format'] as String,
      fileSize: json['fileSize'] as int,
      coverHash: json['coverHash'] as String?,
      publisherPeerId: json['publisherPeerId'] as String,
      publisherUserId: json['publisherUserId'] as String,
      publisherDisplayName: json['publisherDisplayName'] as String,
      advertisedAt: json['advertisedAt'] as int,
      ttlSeconds: json['ttlSeconds'] as int,
    );
  }
}

/// A known source for a piece of content — a peer that claims to have it.
@immutable
class ContentSource {
  const ContentSource({
    required this.advertisement,
    required this.peerAddress,
    required this.peerPort,
    required this.lastSeen,
    required this.isReachable,
  });

  final ContentAdvertisement advertisement;
  final String peerAddress;
  final int peerPort;
  final int lastSeen;
  final bool isReachable;

  bool get isStale {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastSeen > 60000;
  }
}
