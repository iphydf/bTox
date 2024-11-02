import 'dart:typed_data';

import 'package:btox/net/bin_decoder.dart';
import 'package:btox/net/crypto.dart';
import 'package:udp/udp.dart';

/// 1 bit	Transport Protocol	UDP = 0, TCP = 1
/// 7 bit	Address Family	2 = IPv4, 10 = IPv6
/// 4 | 16	IP address	4 bytes for IPv4, 16 bytes for IPv6
/// 2	Port Number	Port number
/// 32	Public Key	Node ID
final class NodeInfo {
  final bool isTcp;
  final bool isIpv6;
  final Uint8List address;
  final Port port;
  final PublicKey publicKey;

  const NodeInfo(
      this.isTcp, this.isIpv6, this.address, this.port, this.publicKey);

  factory NodeInfo.decode(BinDecoder bd) {
    final proto = bd.readUint08();
    final isTcp = proto & 0x80 == 0x80;
    final isIpv6 = proto & 0x7F == 10;
    final address = bd.readBytes(isIpv6 ? 16 : 4);
    final port = Port(bd.readUint16());
    final publicKey = PublicKey(bd.readBytes(32));
    return NodeInfo(isTcp, isIpv6, address, port, publicKey);
  }

  @override
  String toString() {
    return '$runtimeType{isTcp: $isTcp, isIpv6: $isIpv6, address: $address, port: ${port.value}, publicKey: $publicKey}';
  }
}
