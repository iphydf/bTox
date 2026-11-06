import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/messages/text_before_zero.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const format = TextBeforeZero();

  test('reads the text before the first zero byte', () {
    expect(
      format.read(
        Uint8List.fromList([...utf8.encode('Grüße ✓'), 0, 0, 0xff, 0, 1]),
      ),
      'Grüße ✓',
    );
  });

  test('leaves messages without a zero byte alone', () {
    expect(format.read(utf8.encode('just text')), isNull);
  });
}
