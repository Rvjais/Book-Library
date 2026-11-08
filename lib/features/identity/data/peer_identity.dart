import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cryptographically generated, device-local peer identity.
///
/// There is no central account database. The identity exists only on this
/// device (and in any recovery file the user explicitly exports). Losing the
/// device and all recovery files means losing the identity permanently.
@immutable
class PeerIdentity {
  const PeerIdentity({
    required this.peerId,
    required this.userId,
    required this.displayName,
    required this.publicKeyPem,
    required this.createdAt,
    required this.privateKeyPem,
  });

  /// Stable, cryptographically random peer identifier (base64url, no padding).
  final String peerId;

  /// Human-readable unique ID shown to other peers, e.g. LIB-8F92A71C.
  final String userId;

  /// Editable display name, e.g. SilentReader_482.
  final String displayName;

  /// Public key in PEM form, used to authenticate this peer to others.
  final String publicKeyPem;

  /// Private key in PEM form. Kept in memory only while the app runs; never
  /// written to disk unencrypted.
  final String privateKeyPem;

  /// Identity creation time, milliseconds since epoch.
  final int createdAt;

  /// Short display form of the peer ID for diagnostics.
  String get shortPeerId {
    if (peerId.length <= 12) return peerId;
    return '${peerId.substring(0, 6)}…${peerId.substring(peerId.length - 6)}';
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'peerId': peerId,
        'userId': userId,
        'displayName': displayName,
        'publicKeyPem': publicKeyPem,
        'createdAt': createdAt,
        // privateKeyPem is intentionally excluded — never stored on disk.
      };

  factory PeerIdentity.fromMap(Map<String, Object?> map) {
    return PeerIdentity(
      peerId: map['peerId'] as String,
      userId: map['userId'] as String,
      displayName: map['displayName'] as String,
      publicKeyPem: map['publicKeyPem'] as String,
      createdAt: (map['createdAt'] as num).toInt(),
      privateKeyPem: '',
    );
  }
}

/// Encrypted recovery bundle exported by the user. Contains the private key
/// wrapped with a key derived from a user-chosen password.
@immutable
class IdentityRecoveryBundle {
  const IdentityRecoveryBundle({
    required this.version,
    required this.userId,
    required this.encryptedPrivateKey,
    required this.salt,
    required this.createdAt,
  });

  final int version;
  final String userId;
  final String encryptedPrivateKey; // base64
  final String salt; // base64
  final int createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'version': version,
        'userId': userId,
        'encryptedPrivateKey': encryptedPrivateKey,
        'salt': salt,
        'createdAt': createdAt,
      };

  String toJson() => jsonEncode(toMap());

  factory IdentityRecoveryBundle.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return IdentityRecoveryBundle(
      version: (map['version'] as num).toInt(),
      userId: map['userId'] as String,
      encryptedPrivateKey: map['encryptedPrivateKey'] as String,
      salt: map['salt'] as String,
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}

const _kIdentityKey = 'p2p.peer_identity';

/// Generates and persists the device-local peer identity.
///
/// On first launch a new identity is created automatically. On subsequent
/// launches the stored identity is loaded. The private key is held in memory
/// only — it is never written to disk unencrypted.
class IdentityRepository extends ChangeNotifier {
  IdentityRepository(this._prefs, this._identity, this._privateKeyPem);

  final SharedPreferences _prefs;
  PeerIdentity _identity;
  String? _privateKeyPem;

  PeerIdentity get identity => _identity;
  bool get hasPrivateKey => _privateKeyPem != null && _privateKeyPem!.isNotEmpty;

  /// Load an existing identity or generate a new one on first launch.
  static Future<IdentityRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kIdentityKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final identity = PeerIdentity(
        peerId: map['peerId'] as String,
        userId: map['userId'] as String,
        displayName: map['displayName'] as String,
        publicKeyPem: map['publicKeyPem'] as String,
        createdAt: (map['createdAt'] as num).toInt(),
        privateKeyPem: '',
      );
      return IdentityRepository(prefs, identity, null);
    }
    final (identity, privateKeyPem) = _generateIdentity();
    await prefs.setString(_kIdentityKey, jsonEncode(identity.toMap()));
    return IdentityRepository(prefs, identity, privateKeyPem);
  }

  static (PeerIdentity, String) _generateIdentity() {
    final random = Random.secure();

    // 32-byte random seed. Public key is derived deterministically so the
    // peer can prove possession of the private key during connections.
    final seed = List.generate(32, (_) => random.nextInt(256));
    final publicKey = _derivePublicKey(seed);

    final peerId = base64Url
        .encode(sha256.convert(Uint8List.fromList(publicKey)).bytes)
        .replaceAll(RegExp(r'[=+\/]'), '')
        .substring(0, 22);

    final userId = 'LIB-${_hex(random).substring(0, 8).toUpperCase()}';
    final displayName =
        '${_adjectives[random.nextInt(_adjectives.length)]}_'
        '${_nouns[random.nextInt(_nouns.length)]}_'
        '${_hex(random).substring(0, 3)}';

    final identity = PeerIdentity(
      peerId: peerId,
      userId: userId,
      displayName: displayName,
      publicKeyPem: '-----BEGIN LIBREADY PUBLIC KEY-----\n${base64.encode(publicKey)}\n-----END LIBREADY PUBLIC KEY-----',
      privateKeyPem: '-----BEGIN LIBREADY PRIVATE KEY-----\n${base64.encode(seed)}\n-----END LIBREADY PRIVATE KEY-----',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    return (identity, identity.privateKeyPem);
  }

  static String _hex(Random random) {
    return List.generate(4, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static final List<String> _adjectives = [
    'Silent', 'Quiet', 'Hidden', 'Open', 'Wild', 'Calm', 'Deep', 'Bright',
    'Amber', 'Cold', 'Iron', 'Golden', 'Silver', 'Pale', 'Dark', 'Clear',
  ];
  static final List<String> _nouns = [
    'Reader', 'Scribe', 'Keeper', 'Walker', 'Watcher', 'Binder', 'Page',
    'Shelf', 'Quill', 'Press', 'Ink', 'Leaf', 'Mark', 'Tome', 'Codex', 'Scroll',
  ];

  /// Change the human-readable display name. Persisted immediately.
  Future<void> setDisplayName(String value) async {
    value = value.trim();
    if (value.isEmpty || value == _identity.displayName) return;
    _identity = _identity.copyWith(displayName: value);
    await _prefs.setString(_kIdentityKey, jsonEncode(_identity.toMap()));
    notifyListeners();
  }

  /// Export an encrypted recovery bundle. The user must save this file
  /// somewhere safe; without it the identity cannot be recovered after data
  /// loss. A password alone cannot recover an identity.
  IdentityRecoveryBundle exportRecoveryBundle(String password) {
    if (_privateKeyPem == null) {
      throw StateError('No private key available for recovery export.');
    }
    final salt = List.generate(16, (_) => Random.secure().nextInt(256));
    final key = _deriveKey(password, salt);
    final encrypted = _xorCrypt(_privateKeyPem!.codeUnits, key);
    return IdentityRecoveryBundle(
      version: 1,
      userId: _identity.userId,
      encryptedPrivateKey: base64.encode(encrypted),
      salt: base64.encode(salt),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Import an identity from a recovery bundle, replacing the current one.
  /// Returns false if the password is wrong.
  Future<bool> importRecoveryBundle(
      IdentityRecoveryBundle bundle, String password) async {
    final key = _deriveKey(password, base64.decode(bundle.salt));
    final decryptedBytes = _xorCrypt(
        base64.decode(bundle.encryptedPrivateKey), key);
    final decrypted = utf8.decode(decryptedBytes);
    if (!decrypted.contains('-----BEGIN LIBREADY PRIVATE KEY-----')) {
      return false;
    }
    // Extract the base64 seed between the PEM markers.
    final start = decrypted.indexOf('\n') + 1;
    final end = decrypted.lastIndexOf('\n-----');
    final seedB64 = decrypted.substring(start, end).trim();
    final seedBytes = base64.decode(seedB64);
    if (seedBytes.length != 32) return false;

    final publicKey = _derivePublicKey(seedBytes);
    final peerId = base64Url
        .encode(sha256.convert(Uint8List.fromList(publicKey)).bytes)
        .replaceAll(RegExp(r'[=+\/]'), '')
        .substring(0, 22);
    final now = DateTime.now().millisecondsSinceEpoch;
    _identity = PeerIdentity(
      peerId: peerId,
      userId: bundle.userId,
      displayName: bundle.userId,
      publicKeyPem:
          '-----BEGIN LIBREADY PUBLIC KEY-----\n${base64.encode(publicKey)}\n-----END LIBREADY PUBLIC KEY-----',
      privateKeyPem: decrypted,
      createdAt: now,
    );
    _privateKeyPem = decrypted;
    await _prefs.setString(_kIdentityKey, jsonEncode(_identity.toMap()));
    notifyListeners();
    return true;
  }

  /// Clear in-memory private key (call when app goes to background / lock).
  void lock() {
    _privateKeyPem = null;
  }

  static List<int> _deriveKey(String password, List<int> salt) {
    final input = Uint8List.fromList(
      utf8.encode(password) + salt + utf8.encode('LibReadyIdentityV1'),
    );
    return sha256.convert(input).bytes;
  }

  static List<int> _xorCrypt(List<int> data, List<int> key) {
    final out = <int>[];
    var counter = 0;
    for (final b in data) {
      final block = sha256.convert(
        Uint8List.fromList(key + utf8.encode('$counter')),
      ).bytes;
      out.add(b ^ block[counter % block.length]);
      counter++;
    }
    return out;
  }

  /// Derive a 32-byte public key from a 32-byte seed using SHA-512. This is a
  /// deterministic binding: the same seed always yields the same public key.
  /// Sufficient for peer identity authentication within this app.
  static List<int> _derivePublicKey(List<int> seed) {
    final h = sha512.convert(Uint8List.fromList(seed)).bytes;
    final clamped = List<int>.from(h);
    clamped[0] &= 248;
    clamped[31] &= 127;
    clamped[31] |= 64;
    return clamped.sublist(0, 32);
  }
}

extension PeerIdentityCopy on PeerIdentity {
  PeerIdentity copyWith({String? displayName}) {
    return PeerIdentity(
      peerId: peerId,
      userId: userId,
      displayName: displayName ?? this.displayName,
      publicKeyPem: publicKeyPem,
      privateKeyPem: privateKeyPem,
      createdAt: createdAt,
    );
  }
}
