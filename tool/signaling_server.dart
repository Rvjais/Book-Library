import 'dart:convert';
import 'dart:io';

/// A minimal rendezvous/signaling server for LibReady P2P discovery.
///
/// This server does NOT store book files. It only helps peers exchange
/// connection metadata so they can establish direct device-to-device
/// connections across NATs.
///
/// Run with: `dart run bin/signaling_server.dart`
/// Or compile: `dart compile exe bin/signaling_server.dart`
///
/// The server listens on a WebSocket endpoint (default ws://0.0.0.0:8080).
/// Peers connect, register their identity, advertise content hashes, and
/// query for peers sharing specific content.
class SignalingServer {
  SignalingServer({this.port = 8080});

  final int port;

  HttpServer? _server;
  final Map<String, WebSocket> _peers = {}; // peerId -> WebSocket
  final Map<String, Map<String, dynamic>> _advertisements = {};
  // contentHash -> {peerId: advertisement}

  /// Start the signaling server.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('LibReady signaling server listening on :$port');

    await for (final request in _server!) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handlePeer(socket);
      } else {
        request.response
          ..statusCode = 404
          ..close();
      }
    }
  }

  void _handlePeer(WebSocket socket) {
    String? peerId;

    socket.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final type = json['type'] as String?;
          final from = json['fromPeerId'] as String?;
          final to = json['toPeerId'] as String?;
          final payload = json['payload'] as Map<String, dynamic>? ?? {};

          switch (type) {
            case 'register':
              if (from != null) {
                peerId = from;
                _peers[from] = socket;
                print('Peer registered: $from');
              }
              break;
            case 'advertisement':
              if (from != null) {
                final contentHash = payload['contentHash'] as String?;
                if (contentHash != null) {
                  _advertisements.putIfAbsent(
                    contentHash,
                    () => <String, dynamic>{},
                  );
                  (_advertisements[contentHash] as Map)
                    [from] = {
                    'peerId': from,
                    'title': payload['title'],
                    'author': payload['author'],
                    'format': payload['format'],
                    'fileSize': payload['fileSize'],
                    'port': payload['port'],
                    'publicAddress': payload['publicAddress'],
                    'publicPort': payload['publicPort'],
                    'localAddress': payload['localAddress'],
                    'advertisedAt': DateTime.now().millisecondsSinceEpoch,
                    'ttlSeconds': payload['ttlSeconds'] ?? 3600,
                  };
                  print(
                    'Advertisement from $from: $contentHash (${payload['title']})',
                  );
                }
              }
              break;
            case 'withdraw':
              if (from != null) {
                final contentHash = payload['contentHash'] as String?;
                if (contentHash != null) {
                  final ads = _advertisements[contentHash];
                  if (ads != null) {
                    (ads as Map).remove(from);
                    if ((ads as Map).isEmpty) {
                      _advertisements.remove(contentHash);
                    }
                  }
                  print('Peer $from withdrew: $contentHash');
                }
              }
              break;
            case 'query':
              if (from != null) {
                final contentHash = payload['contentHash'] as String?;
                if (contentHash != null) {
                  final ads = _advertisements[contentHash];
                  if (ads != null) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final validSources = <Map<String, dynamic>>[];
                    (ads as Map).forEach((pid, ad) {
                      final adMap = ad as Map;
                      final ttl = adMap['ttlSeconds'] as int? ?? 3600;
                      final advertisedAt =
                          adMap['advertisedAt'] as int? ?? 0;
                      if (now - advertisedAt < ttl * 1000) {
                        validSources.add(Map<String, dynamic>.from(adMap));
                      }
                    });
                    socket.add(jsonEncode(<String, dynamic>{
                      'type': 'peer-list',
                      'fromPeerId': 'server',
                      'toPeerId': from,
                      'payload': <String, dynamic>{
                        'contentHash': contentHash,
                        'sources': validSources,
                      },
                    }));
                  }
                }
              }
              break;
            case 'offer':
            case 'answer':
            case 'ice-candidate':
              if (to != null) {
                final targetSocket = _peers[to];
                if (targetSocket != null && targetSocket != socket) {
                  targetSocket.add(jsonEncode(<String, dynamic>{
                    'type': type,
                    'fromPeerId': from,
                    'toPeerId': to,
                    'payload': payload,
                  }));
                }
              }
              break;
          }
        } catch (_) {
          // Malformed message — ignore.
        }
      },
      onDone: () {
        if (peerId != null) {
          _peers.remove(peerId);
          // Remove all advertisements from this peer
          final toRemove = <String>[];
          _advertisements.forEach((hash, ads) {
            (ads as Map).remove(peerId);
            if ((ads as Map).isEmpty) {
              toRemove.add(hash);
            }
          });
          for (final hash in toRemove) {
            _advertisements.remove(hash);
          }
          print('Peer disconnected: $peerId');
        }
      },
      onError: (_) {
        if (peerId != null) {
          _peers.remove(peerId);
        }
      },
      cancelOnError: false,
    );
  }

  /// Stop the signaling server.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    for (final socket in _peers.values) {
      socket.close();
    }
    _peers.clear();
    _advertisements.clear();
  }
}

void main() async {
  final server = SignalingServer();
  await server.start();
}
