import 'dart:io';

import 'package:btox/net/bin_encoder.dart';
import 'package:btox/net/hex.dart';
import 'package:btox/net/packet.dart';
import 'package:btox/net/transport/transport.dart';
import 'package:sodium/sodium.dart';
import 'package:udp/udp.dart';

final class UdpTransport extends Transport {
  final UDP _udp;

  const UdpTransport(this._udp);

  @override
  void listen(void Function(Datagram? datagram) callback) {
    _udp.asStream().listen(callback);
  }

  @override
  Future<int> send(
      InternetAddress address, Port port, Packet packet, Sodium sodium) {
    final bytes = BinEncoder.encode((be) => packet.encode(be, sodium));
    print(
        'Send ${bytes.length} bytes to ${address.address}:${port.value}: $packet');
    print(hexEncode(bytes));
    return _udp.send(
      bytes,
      Endpoint.unicast(address, port: port),
    );
  }

  static Future<UdpTransport> bind(InternetAddress address, Port port) async {
    final udp = await UDP.bind(Endpoint.any(port: Port(33445)));
    return UdpTransport(udp);
  }
}
