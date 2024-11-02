import 'dart:io';

import 'package:btox/net/bin_decoder.dart';
import 'package:btox/net/bin_encoder.dart';
import 'package:btox/net/packet.dart';
import 'package:btox/net/transport/transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:sodium/sodium.dart';
import 'package:udp/udp.dart';

final class WebSocketTransport extends Transport {
  final WebSocketChannel _ws;

  const WebSocketTransport(this._ws);

  @override
  void listen(void Function(Datagram? datagram) callback) {
    _ws.stream.listen((event) {
      print('WebSocket packet: $event');
    });
  }

  @override
  Future<int> send(
      InternetAddress address, Port port, Packet packet, Sodium sodium) async {
    final bytes = BinEncoder.encode((be) =>
        _WebSocketProxyPacket(address, port, packet).encode(be, sodium));
    _ws.sink.add(bytes);
    return bytes.length;
  }

  static WebSocketTransport connect(Uri uri) {
    final webSocket = WebSocketChannel.connect(uri);
    return WebSocketTransport(webSocket);
  }
}

final class _WebSocketProxyPacket {
  final InternetAddress host;
  final Port port;
  final Packet packet;

  const _WebSocketProxyPacket(this.host, this.port, this.packet);

  factory _WebSocketProxyPacket.decode(BinDecoder bd) {
    final addrLen = bd.readUint08();
    final host = InternetAddress.fromRawAddress(bd.readBytes(addrLen));
    final port = Port(bd.readUint16());
    final packet = Packet.decode(bd);
    return _WebSocketProxyPacket(host, port, packet);
  }

  void encode(BinEncoder be, Sodium sodium) {
    final addr = host.rawAddress;
    be.writeUint08(addr.length);
    be.writeBytes(addr);
    be.writeUint16(port.value);
    packet.encode(be, sodium);
  }

  @override
  String toString() {
    return '$runtimeType{host: $host, port: $port}';
  }
}
