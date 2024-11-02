import 'package:btox/btox_state.dart';
import 'package:btox/contact_list_page.dart';
import 'package:btox/db/database.dart';
import 'package:btox/net/dht.dart';
import 'package:btox/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

final class BtoxApp extends StatelessWidget {
  final Database database;
  final Store<BtoxState> store;
  final Dht dht;

  const BtoxApp({
    super.key,
    required this.database,
    required this.store,
    required this.dht,
  });

  @override
  Widget build(BuildContext context) {
    return StoreProvider<BtoxState>(
      store: store,
      child: MaterialApp(
        title: Strings.title,
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: ContactListPage(
          title: Strings.title,
          database: database,
          dht: dht,
        ),
      ),
    );
  }
}
