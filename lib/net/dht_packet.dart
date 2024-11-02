import 'package:btox/net/bin_decoder.dart';
import 'package:btox/net/bin_encoder.dart';
import 'package:btox/net/crypto.dart';
import 'package:btox/net/dht_state.dart';
import 'package:btox/net/model/node_info.dart';
import 'package:btox/net/packet.dart';
import 'package:sodium/sodium.dart' show Sodium;

final class DhtNodesRequest extends PlaintextPayload {
  final PublicKey publicKey;

  const DhtNodesRequest(this.publicKey);

  @override
  void encode(BinEncoder be, Sodium sodium) {
    be.writeBytes(publicKey.toBytes());
  }

  @override
  String toString() {
    return '$runtimeType{publicKey: $publicKey}';
  }
}

final class DhtNodesResponse extends PlaintextPayload {
  final List<NodeInfo> nodes;

  const DhtNodesResponse(this.nodes);

  /// Byte 0: number of nodes
  /// Bytes 1..n: nodes
  factory DhtNodesResponse.decode(BinDecoder bd, DhtState state) {
    final nodeCount = bd.readUint08();
    final nodes = <NodeInfo>[];
    for (var i = 0; i < nodeCount; i++) {
      nodes.add(NodeInfo.decode(bd));
    }
    return DhtNodesResponse(nodes);
  }

  @override
  void encode(BinEncoder be, Sodium sodium) {
    throw UnimplementedError();
  }

  @override
  String toString() {
    return '$runtimeType{nodes: $nodes}';
  }
}

final class DhtPacket<T extends PlaintextPayload> extends PlaintextPayload {
  final PublicKey senderPublicKey;
  final Nonce nonce;
  final EncryptedPayload<T> payload;

  const DhtPacket(this.senderPublicKey, this.nonce, this.payload);

  factory DhtPacket.fromPlain(
      T payload, KeyPair keyPair, PublicKey receiverPublicKey, Sodium sodium) {
    final nonce = Nonce.random(sodium);
    return DhtPacket(
      keyPair.publicKey,
      nonce,
      EncryptedOutboundPayload(
        keyPair.secretKey,
        receiverPublicKey,
        nonce,
        payload,
      ),
    );
  }

  @override
  void encode(BinEncoder be, Sodium sodium) {
    be.writeBytes(senderPublicKey.toBytes());
    be.writeBytes(nonce.toBytes());
    payload.encode(be, sodium);
  }

  @override
  String toString() {
    return '$runtimeType{senderPublicKey: $senderPublicKey, nonce: $nonce, payload: $payload}';
  }

  DhtPacket<U> withPayload<U extends PlaintextPayload>(
      EncryptedPayload<U> payload) {
    return DhtPacket(senderPublicKey, nonce, payload);
  }

  static DhtPacket<DecryptedPayload> decode(BinDecoder bd, DhtState state) {
    final senderPublicKey = PublicKey(bd.readBytes(32));
    final nonce = Nonce(bd.readBytes(24));
    final cipherText = bd.readBytesToEnd();
    return DhtPacket(
        senderPublicKey,
        nonce,
        EncryptedInboundPayload.decrypt(
            EncryptedInboundPayload(state.keyPair.secretKey, senderPublicKey,
                nonce, EncodedPayload(cipherText)),
            state.sodium));
  }
}

final class DhtRpcPacket<T extends PlaintextPayload> extends PlaintextPayload {
  final T payload;
  final int pingId;

  const DhtRpcPacket(this.payload, this.pingId);

  /// Bytes 0..n-8: payload
  /// Bytes n-8..n: pingId
  @override
  void encode(BinEncoder be, Sodium sodium) {
    payload.encode(be, sodium);
    be.writeUint64(pingId);
  }

  @override
  String toString() {
    return '$runtimeType{payload: $payload, pingId: $pingId}';
  }
}
