import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:toxcore/bytes.dart';
import 'package:toxcore/messagepack.dart';
import 'package:toxcore/tox_constants.dart';

final class PublicKey extends CryptoBytes implements Comparable<PublicKey> {
  static const kLength = 32;

  PublicKey(super.bytes);

  factory PublicKey.fromJson(String value) =>
      PublicKey(Uint8List.fromList(hex.decode(value)));

  factory PublicKey.unpack(Unpacker unpacker) =>
      PublicKey(unpacker.unpackBinary()!);

  @override
  int get length => PublicKey.kLength;

  @override
  int compareTo(PublicKey other) => compareBytes(bytes, other.bytes);
}

final class SecretKey extends CryptoBytes {
  static const kLength = 32;

  SecretKey(super.bytes);

  factory SecretKey.fromJson(String value) =>
      SecretKey(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => SecretKey.kLength;
}

/// Makes a group key pair: ours in a group, or the group's own, whose public
/// key is the chat ID and which only the founder has.
final class GroupSecretKey extends CryptoBytes {
  static const kLength = 32;

  GroupSecretKey(super.bytes);

  factory GroupSecretKey.fromJson(String value) =>
      GroupSecretKey(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => GroupSecretKey.kLength;
}

final class GroupChatId extends CryptoBytes {
  GroupChatId(super.bytes);

  factory GroupChatId.fromJson(String value) =>
      GroupChatId(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => toxGroupChatIdSize;
}

final class ConferenceId extends CryptoBytes {
  ConferenceId(super.bytes);

  @override
  int get length => toxConferenceIdSize;
}

final class FileId extends CryptoBytes {
  FileId(super.bytes);

  factory FileId.fromJson(String value) =>
      FileId(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => toxFileIdLength;
}

final class ToxAddress extends CryptoBytes {
  static const kLength = 38;
  static const kChecksumLength = 2;

  ToxAddress(super.bytes);

  factory ToxAddress.fromString(String value) =>
      ToxAddress(Uint8List.fromList(hex.decode(value)));

  factory ToxAddress.of(PublicKey publicKey, ToxAddressNospam nospam) {
    final bytes = Uint8List(kLength)..setAll(0, publicKey.bytes);
    bytes.buffer.asByteData().setUint32(PublicKey.kLength, nospam.value);
    bytes.setAll(kLength - kChecksumLength, _checksum(bytes));
    return ToxAddress(bytes);
  }

  bool get hasValidChecksum {
    final checksum = _checksum(bytes);
    final end = kLength - kChecksumLength;
    return bytes[end] == checksum[0] && bytes[end + 1] == checksum[1];
  }

  static List<int> _checksum(Uint8List bytes) {
    final checksum = [0, 0];
    for (var i = 0; i < PublicKey.kLength + ToxAddressNospam.kLength; i++) {
      checksum[i % 2] ^= bytes[i];
    }
    return checksum;
  }

  @override
  int get length => ToxAddress.kLength;
  ToxAddressNospam get nospam => ToxAddressNospam(
    ByteData.sublistView(bytes).getUint32(PublicKey.kLength),
  );
  PublicKey get publicKey =>
      PublicKey(Uint8List.sublistView(bytes, 0, PublicKey.kLength));
}

final class ToxAddressNospam {
  static const kLength = 4;

  final int value;

  ToxAddressNospam(this.value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError('Nospam must be a 32-bit unsigned integer');
    }
  }

  @override
  int get hashCode => value;

  @override
  bool operator ==(Object other) =>
      other is ToxAddressNospam && other.value == value;

  @override
  String toString() => 'ToxAddressNospam($value)';
}

abstract class CryptoBytes {
  Uint8List _bytes;

  CryptoBytes(Uint8List bytes) : _bytes = bytes.asUnmodifiableView() {
    if (_bytes.length != length) {
      throw ArgumentError('Invalid $runtimeType length: ${_bytes.length}');
    }
  }

  Uint8List get bytes => _bytes;

  // They're map keys everywhere, and never change.
  @override
  late final int hashCode = memHash(_bytes);

  int get length;

  @override
  bool operator ==(Object other) {
    if (other is CryptoBytes &&
        other.runtimeType == runtimeType &&
        memEquals(_bytes, other._bytes)) {
      // Speed up future comparisons by making equality a pointer comparison.
      _bytes = other._bytes;
      return true;
    }
    return false;
  }

  String toJson() => hex.encode(_bytes).toUpperCase();

  @override
  String toString() => '$runtimeType(${toJson()})';
}
