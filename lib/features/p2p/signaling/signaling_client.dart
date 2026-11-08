import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:libready/features/p2p/stun/stun_client.dart';
import 'package:meta/meta.dart';

/// A message exchanged through the rendezvous signaling server.
@immutable
class SignalMessage {
  const SignalMessage({
    required this.type,
    required this.fromPeerId,
    required this.toPeerId,
    required this.payload,
  });

  /// Message type: 'offer', 'answer', 'ice-candidate', 'register', 'query',
  /// 'advertisement', 'peer-list'.
  final String type;
  final String fromPeerId;
  final String? toPeerId;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'fromPeerId': fromPeerId,
        if (toPeerId != null) 'toPeerId': toPeerId,
        'payload': payload,
      };

  factory SignalMessage.fromJson(Map<String, dynamic> json) {
    return SignalMessage(
      type: json['type'] as String,
      fromPeerId: json['fromPeerId'] as String,
      toPeerId: json['toPeerId'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// Connects to a rendezvous signaling server to enable cross-network peer
/// discovery and connection setup.
///
/// The signaling server does NOT store book files. It only helps peers
/// exchange connection metadata (public addresses, content advertisements)
/// so they can establish direct device-to-device connections.
class SignalingClient {
  SignalingClient({
    required this.peerId,
    required this.serverUrl,
    this.reconnectInterval = const Duration(seconds: 5),
  });

  final String peerId;
  final String serverUrl; // ws:// or wss:// hostname:port
  final Duration reconnectInterval;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  final StreamController<SignalMessage> _messageController =
      StreamController<SignalMessage>.broadcast();
  bool _isConnected = false;

  Stream<SignalMessage> get messageStream => _messageController.stream;

  bool get isConnected => _isConnected && _socket != null;

  /// Connect to the signaling server and register this peer.
  Future<void> connect() async {
    try {
      _socket = await WebSocket.connect(serverUrl);
      _isConnected = true;
      _socket!.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(SignalMessage.fromJson(json));
          } catch (_) {
            // Malformed message — ignore.
          }
        },
        onDone: () {
          _socket = null;
          _isConnected = false;
          _scheduleReconnect();
        },
        onError: (_) {
          _socket = null;
          _isConnected = false;
          _scheduleReconnect();
        },
      );
      await _send(SignalMessage(
        type: 'register',
        fromPeerId: peerId,
        toPeerId: null,
        payload: <String, dynamic>{},
      ));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(reconnectInterval, (_) {
      unawaited(connect());
    });
  }

  Future<void> _send(SignalMessage message) async {
    if (!_isConnected || _socket == null) return;
    _socket!.add(jsonEncode(message.toJson()));
  }

  /// Advertise that this peer is sharing a piece of content.
  Future<void> advertiseContent({
    required String contentHash,
    required String title,
    required String author,
    required String format,
    required int fileSize,
    required int port,
  }) async {
    final stun = StunClient();
    StunAddress? publicAddr;
    try {
      publicAddr = await stun.discover();
    } catch (_) {
      // STUN failed — advertise with local address only
    }

    await _send(SignalMessage(
      type: 'advertisement',
      fromPeerId: peerId,
      toPeerId: null,
      payload: <String, dynamic>{
        'contentHash': contentHash,
        'title': title,
        'author': author,
        'format': format,
        'fileSize': fileSize,
        'port': port,
        'publicAddress': publicAddr?.address,
        'publicPort': publicAddr?.port,
        'localAddress': InternetAddress.anyIPv4.address,
        'ttlSeconds': 3600,
      },
    ));
  }

  /// Query the server for peers sharing a specific content hash.
  Future<void> queryContent(String contentHash) async {
    await _send(SignalMessage(
      type: 'query',
      fromPeerId: peerId,
      toPeerId: null,
      payload: <String, dynamic>{
        'contentHash': contentHash,
      },
    ));
  }

  /// Send an ICE offer to a specific peer (initiates direct connection).
  Future<void> sendOffer({
    required String toPeerId,
    required String contentHash,
    required Map<String, dynamic> sdp,
  }) async {
    await _send(SignalMessage(
      type: 'offer',
      fromPeerId: peerId,
      toPeerId: toPeerId,
      payload: <String, dynamic>{
        'contentHash': contentHash,
        'sdp': sdp,
      },
    ));
  }

  /// Send an ICE answer in response to an offer.
  Future<void> sendAnswer({
    required String toPeerId,
    required String contentHash,
    required Map<String, dynamic> sdp,
  }) async {
    await _send(SignalMessage(
      type: 'answer',
      fromPeerId: peerId,
      toPeerId: toPeerId,
      payload: <String, dynamic>{
        'contentHash': contentHash,
        'sdp': sdp,
      },
    ));
  }

  /// Send an ICE candidate to a peer during connection setup.
  Future<void> sendIceCandidate({
    required String toPeerId,
    required String contentHash,
    required Map<String, dynamic> candidate,
  }) async {
    await _send(SignalMessage(
      type: 'ice-candidate',
      fromPeerId: peerId,
      toPeerId: toPeerId,
      payload: <String, dynamic>{
        'contentHash': contentHash,
        'candidate': candidate,
      },
    ));
  }

  /// Withdraw an advertisement (stop sharing).
  Future<void> withdrawContent(String contentHash) async {
    await _send(SignalMessage(
      type: 'withdraw',
      fromPeerId: peerId,
      toPeerId: null,
      payload: <String, dynamic>{
        'contentHash': contentHash,
      },
    ));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isConnected = false;
    _messageController.close();
  }
}
