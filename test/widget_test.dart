import 'dart:io';

import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';
import 'package:btox/main.dart';
import 'package:btox/net/dht.dart';
import 'package:btox/net/packet.dart';
import 'package:btox/net/transport/transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:udp/udp.dart';

// The database can't be constructed/torn down in the Flutter test framework
// setUp and tearDown functions as that leads to leaks being reported due to
// Drift's timers being created during the test and then only torn down during
// the tearDown after being reported as leaks at the test end.
void main() {
  final String allZeroToxId =
      String.fromCharCodes(Iterable.generate(76, (_) => '0'.codeUnits.first));
  testWidgets('Add contact adds a contact', (WidgetTester tester) async {
    final Database db = Database(NativeDatabase.memory());
    await tester.pumpWidget(BtoxApp(
      database: db,
      store: createStore(),
      dht: Dht.create(await SodiumInit.init(), const TransportMock()),
    ));

    // Check that no contact with all 0s for the public key exists.
    expect(find.textContaining('00000000'), findsNothing);

    // Navigate to the 'add contact' screen.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Fill in the contact data.
    await tester.enterText(find.byKey(const Key('toxId')), allZeroToxId);
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Verify that the contact appeared.
    expect(find.textContaining('00000000'), findsOneWidget);

    await db.close();
  });
}

final class TransportMock extends Transport {
  const TransportMock();

  @override
  void listen(void Function(Datagram? datagram) callback) {}

  @override
  Future<int> send(
      InternetAddress address, Port port, Packet packet, Sodium sodium) async {
    return 0;
  }
}
