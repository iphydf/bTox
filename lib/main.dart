import 'dart:io';

import 'package:btox/btox_app.dart';
import 'package:btox/btox_reducer.dart';
import 'package:btox/btox_state.dart';
import 'package:btox/db/database.dart';
import 'package:btox/db/shared.dart';
import 'package:btox/net/crypto.dart';
import 'package:btox/net/dht.dart';
import 'package:btox/net/transport/udp_transport.dart';
import 'package:flutter/material.dart';
import 'package:redux/redux.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:udp/udp.dart';

void main() async {
  final Database database = constructDb();
  final store = createStore();
  final dht = Dht.create(
    await SodiumInit.init(),
    await UdpTransport.bind(InternetAddress.anyIPv4, Port(33445)),
  );

  dht.bootstrap(
    InternetAddress('144.217.167.73'),
    Port(33445),
    PublicKey.fromHex(
        '7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C'),
  );

  runApp(BtoxApp(
    database: database,
    store: store,
    dht: dht,
  ));
}

Store<BtoxState> createStore() {
  return Store<BtoxState>(
    btoxReducer,
    initialState: BtoxState.initial(),
  );
}
