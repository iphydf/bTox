import 'dart:io';

import 'package:btox/net/model/node_info.dart';
import 'package:btox/net/packet.dart';

final class AddNodeAction {
  final NodeInfo node;

  const AddNodeAction(this.node);
}

final class DhtDatagramAction {
  final InternetAddress address;
  final int port;
  final List<int> data;

  const DhtDatagramAction(this.address, this.port, this.data);
}

final class ReceivedPacketAction<T extends Payload> {
  final Packet<T> packet;

  const ReceivedPacketAction(this.packet);
}
