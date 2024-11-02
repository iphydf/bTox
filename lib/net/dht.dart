import 'dart:io';

import 'package:btox/net/crypto.dart';
import 'package:btox/net/dht_actions.dart';
import 'package:btox/net/dht_middleware.dart';
import 'package:btox/net/dht_packet.dart';
import 'package:btox/net/dht_reducer.dart';
import 'package:btox/net/dht_state.dart';
import 'package:btox/net/packet.dart';
import 'package:btox/net/transport/transport.dart';
import 'package:redux/redux.dart';
import 'package:sodium/sodium.dart' show Sodium;
import 'package:udp/udp.dart';

final class Dht {
  final Sodium _sodium;
  final Store<DhtState> _store;
  final Transport _transport;

  const Dht(this._sodium, this._store, this._transport);

  Future<int> bootstrap(
      InternetAddress address, Port port, PublicKey publicKey) async {
    final dhtKeyPair = _store.state.keyPair;
    return await _transport.send(
      address,
      port,
      Packet(
        PacketKind.nodesRequest,
        DhtPacket.fromPlain(
          DhtRpcPacket(
            DhtNodesRequest(PublicKey.random(_sodium)),
            0x12345678,
          ),
          dhtKeyPair,
          publicKey,
          _sodium,
        ),
      ),
      _sodium,
    );
  }

  factory Dht.create(Sodium sodium, Transport transport) {
    final store = Store<DhtState>(
      dhtReducer,
      initialState: DhtState.initial(
        sodium: sodium,
        keyPair: KeyPair.generate(sodium),
      ),
      middleware: [
        const DhtMiddleware().call,
      ],
    );

    transport.listen((datagram) {
      if (datagram == null) {
        return;
      }
      store.dispatch(DhtDatagramAction(
        datagram.address,
        datagram.port,
        datagram.data,
      ));
    });

    return Dht(sodium, store, transport);
  }
}
