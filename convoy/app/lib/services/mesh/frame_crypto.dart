import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for every frame that leaves the phone over a radio.
///
/// LoRa traffic is receivable by anyone with a Meshtastic node in range, and
/// the default Meshtastic channel key is public, so frames are sealed with
/// ChaCha20-Poly1305 under a key only trip members can derive. This gives
/// confidentiality (nobody can plot the convoy) and authenticity (nobody can
/// inject a fake position or message), regardless of the carrier.
///
/// Envelope: `[0xC5][nonce:12][ciphertext][tag:16]` — 29 bytes of overhead.
class FrameCrypto {
  FrameCrypto({required String tripId, required String tripSecret})
      : _key = SecretKey(sha256.convert(utf8.encode('convoy-mesh-v2:$tripId:$tripSecret')).bytes);

  static const int magic = 0xC5;
  static const int overhead = 1 + 12 + 16;

  final SecretKey _key;
  final _aead = Chacha20.poly1305Aead();
  final _rng = Random.secure();

  Future<Uint8List> seal(Uint8List plain) async {
    final nonce = List<int>.generate(12, (_) => _rng.nextInt(256));
    final box = await _aead.encrypt(plain, secretKey: _key, nonce: nonce);
    return Uint8List.fromList([magic, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Returns null for anything not sealed with this trip's key.
  Future<Uint8List?> open(Uint8List sealed) async {
    if (sealed.length < overhead || sealed[0] != magic) return null;
    final nonce = sealed.sublist(1, 13);
    final cipher = sealed.sublist(13, sealed.length - 16);
    final mac = Mac(sealed.sublist(sealed.length - 16));
    try {
      final plain = await _aead.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: _key);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
