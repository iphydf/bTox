
import 'dart:typed_data';

Uint8List hexDecode(String hex) {
  if (hex.length % 2 != 0) {
    throw ArgumentError('Hex string must have an even number of characters');
  }
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

String hexEncode(Uint8List bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
