import 'dart:typed_data';

import 'package:btox/net/bin_decoder.dart';
import 'package:btox/net/dht_actions.dart';
import 'package:btox/net/dht_packet.dart';
import 'package:btox/net/dht_state.dart';
import 'package:btox/net/hex.dart';
import 'package:btox/net/packet.dart';
import 'package:redux/redux.dart';

final class DhtMiddleware implements MiddlewareClass<DhtState> {
  const DhtMiddleware();

  @override
  dynamic call(Store<DhtState> store, dynamic action, NextDispatcher next) {
    switch (action) {
      case AddNodeAction _:
        print('Add node: ${action.node}');
        break;
      case DhtDatagramAction _:
        print(
            'Datagram from ${action.address}:${action.port} with ${action.data.length} bytes');
        final data = Uint8List.fromList(action.data);
        print(hexEncode(data));
        final packet = Packet.decode(BinDecoder(data));
        store.dispatch(ReceivedPacketAction(packet));
        break;
      case ReceivedPacketAction<EncodedPayload> _:
        print('Received packet: ${action.packet}');
        switch (action.packet.kind) {
          case PacketKind.nodesResponse:
            final response = action.packet.withPayload(DhtPacket.decode(
                BinDecoder(action.packet.payload.data), store.state));
            store.dispatch(ReceivedPacketAction(response));
            break;
          default:
            print('Unknown packet kind: ${action.packet.kind}');
            break;
        }
        break;
      case ReceivedPacketAction<DhtPacket<DecryptedPayload>> _:
        print('Received packet: ${action.packet}');
        switch (action.packet.kind) {
          case PacketKind.nodesResponse:
            final response = action.packet.withPayload(action.packet.payload
                .withPayload(action.packet.payload.payload.withPayload(
                    DhtNodesResponse.decode(
                        BinDecoder(action.packet.payload.payload.payload.data),
                        store.state))));
            store.dispatch(ReceivedPacketAction(response));
            break;
          default:
            print('Unknown packet kind: ${action.packet.kind}');
            break;
        }
        break;
      case ReceivedPacketAction<DhtPacket<DhtNodesResponse>> _:
        print('Received packet: ${action.packet}');
        for (final node in action.packet.payload.payload.payload.nodes) {
          store.dispatch(AddNodeAction(node));
        }
        break;
    }
    return next(action);
  }
}
