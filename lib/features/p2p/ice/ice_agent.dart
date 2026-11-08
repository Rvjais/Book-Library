import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:libready/features/p2p/stun/stun_client.dart';

/// A candidate address for reaching a peer.
@immutable
class IceCandidate {
  const IceCandidate({
    required this.type,
    required this.address,
    required this.port,
    required this.foundation,
    required this.priority,
  });

  /// 'host', 'srflx' (STUN), or 'relay' (TURN).
  final String type;
  final String address;
  final int port;
  final String foundation;
  final int priority;

  String get endpoint => '$address:$port';
}

/// Attempts to establish a direct connection to a peer, trying candidates in
/// priority order (host → STUN → TURN relay). Falls back to a TURN relay if
/// direct connectivity fails.
///
/// Returns a connected [Socket] on success, or throws if no candidate works.
class IceAgent {
  IceAgent({
    this.turnServer,
    this.turnUsername,
    this.turnPassword,
    this.connectionTimeout = const Duration(seconds: 15),
  });

  /// Optional TURN relay server for when direct P2P is blocked by symmetric NAT.
  final String? turnServer;
  final String? turnUsername;
  final String? turnPassword;
  final Duration connectionTimeout;

  /// Try to connect to a peer using the provided candidates.
  ///
  /// Candidates should be sorted by priority (highest first). The first
  /// successful connection is returned.
  Future<Socket> connect(List<IceCandidate> candidates) async {
    var lastError;

    for (final candidate in candidates) {
      try {
        final socket = await Socket.connect(
          candidate.address,
          candidate.port,
          timeout: connectionTimeout,
        );
        return socket;
      } catch (e) {
        lastError = e;
      }
    }

    throw SocketException(
      'Could not establish connection to any candidate: $lastError',
    );
  }

  /// Generate local ICE candidates for this device.
  ///
  /// Includes host candidates (local IPs) and, if STUN succeeds, a srflx
  /// candidate (public address). TURN relay candidates require a TURN server
  /// and are not generated here — they would come from the signaling server.
  static Future<List<IceCandidate>> localCandidates({
    int localPort = 0,
    int foundationCounter = 0,
  }) async {
    final candidates = <IceCandidate>[];

    // Host candidates: local IPv4 addresses
    final interfaces = await NetworkInterface.list();
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            !addr.isLinkLocal) {
          candidates.add(IceCandidate(
            type: 'host',
            address: addr.address,
            port: localPort,
            foundation: 'host${foundationCounter}',
            priority: 100,
          ));
        }
      }
    }

    // STUN server-reflexive candidate
    try {
      final stun = StunClient();
      final publicAddr = await stun.discover();
      if (publicAddr != null) {
        candidates.add(IceCandidate(
          type: 'srflx',
          address: publicAddr.address,
          port: publicAddr.port,
          foundation: 'stun${foundationCounter}',
          priority: 80,
        ));
      }
    } catch (_) {
      // STUN unavailable — skip srflx candidate
    }

    // Sort by priority descending
    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    return candidates;
  }
}

/// Result of an ICE connection attempt.
@immutable
class IceConnectionResult {
  const IceConnectionResult({
    required this.success,
    this.socket,
    this.selectedCandidate,
    this.error,
  });

  final bool success;
  final Socket? socket;
  final IceCandidate? selectedCandidate;
  final String? error;
}
