import 'dart:typed_data';

import 'package:btox/net/bin_decoder.dart';
import 'package:btox/net/bin_encoder.dart';
import 'package:btox/net/crypto.dart';
import 'package:btox/net/hex.dart';
import 'package:sodium/sodium.dart' show Sodium;

final class DecryptedPayload extends PlaintextPayload {
  final Uint8List data;

  const DecryptedPayload(this.data);

  @override
  void encode(BinEncoder be, Sodium sodium) {
    be.writeBytes(data);
  }

  @override
  String toString() {
    return '$runtimeType{data: ${hexEncode(data).substring(0, 4)}...}';
  }
}

final class EncodedPayload extends PlaintextPayload {
  final Uint8List data;

  const EncodedPayload(this.data);

  @override
  void encode(BinEncoder be, Sodium sodium) {
    be.writeBytes(data);
  }

  @override
  String toString() {
    return '$runtimeType{data: ${hexEncode(data).substring(0, 4)}...}';
  }
}

final class EncryptedInboundPayload<T extends PlaintextPayload>
    extends EncryptedPayload<T> {
  const EncryptedInboundPayload(
      super.secretKey, super.publicKey, super.nonce, super.payload);

  @override
  EncryptedInboundPayload<U> withPayload<U extends PlaintextPayload>(
      U payload) {
    return EncryptedInboundPayload(secretKey, publicKey, nonce, payload);
  }

  static EncryptedInboundPayload<DecryptedPayload> decrypt(
      EncryptedPayload<EncodedPayload> payload, Sodium sodium) {
    final decrypted = sodium.crypto.box.openEasy(
      cipherText: payload.payload.data,
      nonce: payload.nonce.toBytes(),
      publicKey: payload.publicKey.toBytes(),
      secretKey: payload.secretKey.toSodium(),
    );
    return EncryptedInboundPayload(payload.secretKey, payload.publicKey,
        payload.nonce, DecryptedPayload(decrypted));
  }
}

final class EncryptedOutboundPayload<T extends PlaintextPayload>
    extends EncryptedPayload<T> {
  const EncryptedOutboundPayload(
      super.secretKey, super.publicKey, super.nonce, super.payload);

  @override
  EncryptedOutboundPayload<U> withPayload<U extends PlaintextPayload>(
      U payload) {
    return EncryptedOutboundPayload(secretKey, publicKey, nonce, payload);
  }
}

sealed class EncryptedPayload<T extends PlaintextPayload> extends Payload {
  final SecretKey secretKey;
  final PublicKey publicKey;
  final Nonce nonce;
  final T payload;

  const EncryptedPayload(
      this.secretKey, this.publicKey, this.nonce, this.payload);

  @override
  // Uint8List encode(Sodium sodium) {
  //   return sodium.crypto.box.easy(
  //     message: payload.encode(sodium),
  //     nonce: nonce.toBytes(),
  //     publicKey: publicKey.toBytes(),
  //     secretKey: secretKey.toSodium(),
  //   );
  // }

  void encode(BinEncoder be, Sodium sodium) {
    be.writeBytes(sodium.crypto.box.easy(
      message: BinEncoder.encode((be) => payload.encode(be, sodium)),
      nonce: nonce.toBytes(),
      publicKey: publicKey.toBytes(),
      secretKey: secretKey.toSodium(),
    ));
  }

  @override
  String toString() {
    return '$runtimeType{secretKey: $secretKey, publicKey: $publicKey, nonce: $nonce, payload: $payload}';
  }

  EncryptedPayload<U> withPayload<U extends PlaintextPayload>(U payload);
}

/// A Protocol Packet is the top level Tox protocol element. All other packet
/// types are wrapped in Protocol Packets. It consists of a Packet Kind and a
/// payload. The binary representation of a Packet Kind is a single byte (8
/// bits). The payload is an arbitrary sequence of bytes.
final class Packet<T extends Payload> extends PlaintextPayload {
  final PacketKind kind;
  final T payload;

  const Packet(this.kind, this.payload);

  /// Byte 0: Packet kind
  /// Bytes 1..n: Payload
  @override
  void encode(BinEncoder be, Sodium sodium) {
    be.writeUint08(kind.value);
    payload.encode(be, sodium);
  }

  @override
  String toString() {
    return '$runtimeType{kind: $kind, payload: $payload}';
  }

  Packet<U> withPayload<U extends Payload>(U payload) {
    return Packet(kind, payload);
  }

  static Packet<EncodedPayload> decode(BinDecoder bd) {
    final kindByte = bd.readUint08();
    final kind = PacketKind.values.firstWhere((k) => k.value == kindByte);
    return Packet(kind, EncodedPayload(bd.readBytesToEnd()));
  }
}

enum PacketKind {
  pingRequest(0x00),
  pingResponse(0x01),
  nodesRequest(0x02),
  nodesResponse(0x04),
  cookieRequest(0x18),
  cookieResponse(0x19),
  cryptoHandshake(0x1a),
  cryptoData(0x1b),
  crypto(0x20),
  lanDiscovery(0x21),
  onionRequest0(0x80),
  onionRequest1(0x81),
  onionRequest2(0x82),
  announceRequest(0x83),
  announceResponse(0x84),
  onionDataRequest(0x85),
  onionDataResponse(0x86),
  onionResponse3(0x8c),
  onionResponse2(0x8d),
  onionResponse1(0x8e),
  bootstrapInfo(0xf0);

  final int value;

  const PacketKind(this.value);
}

sealed class Payload {
  const Payload();

  void encode(BinEncoder be, Sodium sodium);
}

abstract class PlaintextPayload extends Payload {
  const PlaintextPayload();
}
