import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

class StunClient {
  StunClient({this.server = 'stun.l.google.com', this.port = 19302});

  final String server;
  final int port;

  /// Perform a STUN Binding Request and return the mapped public address.
  ///
  /// Returns null if the STUN server is unreachable or the response is
  /// invalid. On failure the caller should fall back to local addresses only.
  Future<StunAddress?> discover() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    try {
      final transactionId = List.generate(16, (_) => 0);
      final request = _buildBindingRequest(transactionId);
      final address = InternetAddress(server);

      socket.send(request, address, port);

      final response = await socket.firstWhere(
        (event) => event == RawSocketEvent.read,
      );
      if (response != RawSocketEvent.read) return null;

      final datagram = socket.receive();
      if (datagram == null) return null;
      return _parseBindingResponse(datagram.data, transactionId);
    } catch (_) {
      return null;
    } finally {
      socket.close();
    }
  }

  Uint8List _buildBindingRequest(List<int> transactionId) {
    // STUN Binding Request: 0x0001, length 0, magic cookie, transaction ID
    final data = Uint8List(20);
    data[0] = 0x00;
    data[1] = 0x01; // Binding Request
    data[2] = 0x00;
    data[3] = 0x00; // Length = 0
    data[4] = 0x21;
    data[5] = 0x12;
    data[6] = 0xA4;
    data[7] = 0x42; // Magic cookie
    data.setRange(8, 24, transactionId);
    return data;
  }

  StunAddress? _parseBindingResponse(Uint8List data, List<int> txnId) {
    if (data.length < 20) return null;
    // Verify magic cookie and transaction ID
    if (data[4] != 0x21 || data[5] != 0x12 || data[6] != 0xA4 ||
        data[7] != 0x42) return null;
    for (var i = 0; i < 16; i++) {
      if (data[8 + i] != txnId[i]) return null;
    }

    // Parse attributes for XOR-MAPPED-ADDRESS (0x0020)
    var offset = 20;
    while (offset + 4 <= data.length) {
      final attrType = (data[offset] << 8) | data[offset + 1];
      final attrLength = (data[offset + 2] << 8) | data[offset + 3];
      offset += 4;
      if (offset + attrLength > data.length) return null;
      if (attrType == 0x0020) {
        // XOR-MAPPED-ADDRESS
        final family = data[offset + 1];
        if (family != 0x01) return null; // IPv4 only
        final port = ((data[offset + 2] ^ 0x21) << 8) |
            (data[offset + 3] ^ 0x12);
        final ip = List<int>.generate(4, (i) {
          return data[offset + 4 + i] ^ _magicCookie[i];
        });
        return StunAddress(
          address: '${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}',
          port: port,
        );
      }
      offset += attrLength;
      // STUN padding to 4-byte boundary
      final padding = (4 - (attrLength % 4)) % 4;
      offset += padding;
    }
    return null;
  }

  static const _magicCookie = [0x21, 0x12, 0xA4, 0x42];
}

/// Public IP:port discovered via STUN.
@immutable
class StunAddress {
  const StunAddress({required this.address, required this.port});

  final String address;
  final int port;

  String get endpoint => '$address:$port';
}
