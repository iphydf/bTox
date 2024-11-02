import 'dart:io';

import 'package:btox/net/packet.dart';
import 'package:sodium/sodium.dart';
import 'package:udp/udp.dart';

abstract class Transport {
  const Transport();

  void listen(void Function(Datagram? datagram) callback);
  Future<int> send(
      InternetAddress address, Port port, Packet packet, Sodium sodium);
}
