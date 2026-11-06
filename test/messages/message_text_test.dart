import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/messages/message_text.dart';
import 'package:btox/models/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList([...utf8.encode('Grüße'), 0, 0xff, 0]);
  final chat = GraphId(Uint8List(GraphId.kLength));

  test('shows each zero byte as \\0, with what follows', () {
    expect(MessageTexts.plain.read(bytes, chat), 'Grüße\\0\ufffd\\0');
  });

  test('in a chat that hides it, shows what follows as its size', () {
    expect(MessageTexts({chat}).read(bytes, chat), 'Grüße\\0[4 bytes]');
    expect(
      MessageTexts({chat}).read(utf8.encode('just text'), chat),
      'just text',
    );
  });
}
