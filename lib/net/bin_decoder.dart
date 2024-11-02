import 'dart:typed_data';

final class BinDecoder {
  final Uint8List data;
  int _offset = 0;

  BinDecoder(this.data);

  Uint8List readBytes(int length) {
    final bytes = data.sublist(_offset, _offset + length);
    _offset += length;
    return bytes;
  }

  Uint8List readBytesToEnd() {
    final bytes = data.sublist(_offset);
    _offset = data.length;
    return bytes;
  }

  int readUint08() {
    return data[_offset++];
  }

  int readUint16() {
    final value = data.buffer.asByteData().getUint16(_offset);
    _offset += 2;
    return value;
  }

  int readUint32() {
    final value = data.buffer.asByteData().getUint32(_offset);
    _offset += 4;
    return value;
  }

  int readUint64() {
    final value = data.buffer.asByteData().getUint64(_offset);
    _offset += 8;
    return value;
  }
}
