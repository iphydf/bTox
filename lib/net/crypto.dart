import 'dart:typed_data';

import 'package:btox/net/hex.dart';
import 'package:sodium/sodium.dart';

sealed class CryptoNumber {
  final Uint8List _data;

  const CryptoNumber(this._data);

  Uint8List toBytes() => _data;

  @override
  String toString() => '${hexEncode(_data).substring(0, 4)}...';
}

final class KeyPair {
  final PublicKey publicKey;
  final SecretKey secretKey;

  const KeyPair(this.publicKey, this.secretKey);

  factory KeyPair.generate(Sodium sodium) {
    final keyPair = sodium.crypto.box.keyPair();
    return KeyPair(
      PublicKey(keyPair.publicKey),
      SecretKey(keyPair.secretKey),
    );
  }

  @override
  String toString() =>
      '$runtimeType{publicKey: $publicKey, secretKey: $secretKey}';
}

final class Nonce extends CryptoNumber {
  const Nonce(super._data);

  factory Nonce.random(Sodium sodium) {
    return Nonce(sodium.randombytes.buf(sodium.crypto.box.nonceBytes));
  }
}

final class PublicKey extends CryptoNumber {
  const PublicKey(super._data);

  /// Create a [PublicKey] from a hex string.
  ///
  /// E.g. "7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C"
  /// will create a [PublicKey] with the same bytes, i.e. {0x7e, 0x56, ...}.
  factory PublicKey.fromHex(String hex) {
    final bytes = hexDecode(hex);
    if (bytes.length != 32) {
      throw ArgumentError('Expected 32 bytes, got ${bytes.length}');
    }
    return PublicKey(bytes);
  }

  factory PublicKey.random(Sodium sodium) {
    return PublicKey(sodium.randombytes.buf(sodium.crypto.box.publicKeyBytes));
  }
}

final class SecretKey {
  final SecureKey _data;

  const SecretKey(this._data);

  SecureKey toSodium() => _data;

  @override
  String toString() => '<redacted>';
}
