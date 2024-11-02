import 'dart:typed_data';

sealed class BinEncoder {
  void writeBytes(Uint8List bytes);
  void writeUint08(int value);
  void writeUint16(int value);
  void writeUint32(int value);
  void writeUint64(int value);

  static Uint8List encode(void Function(BinEncoder) write) {
    final counting = _CountingBinEncoder();
    write(counting);
    final encoder = _BytesBinEncoder(counting.count);
    write(encoder);
    return encoder.data;
  }
}

final class _BytesBinEncoder extends BinEncoder {
  final Uint8List data;
  int _offset = 0;

  _BytesBinEncoder(int length) : data = Uint8List(length);

  int get offset => _offset;

  @override
  void writeBytes(Uint8List bytes) {
    data.setAll(_offset, bytes);
    _offset += bytes.length;
  }

  @override
  void writeUint08(int value) {
    data[_offset++] = value;
  }

  @override
  void writeUint16(int value) {
    data.buffer.asByteData().setUint16(_offset, value);
    _offset += 2;
  }

  @override
  void writeUint32(int value) {
    data.buffer.asByteData().setUint32(_offset, value);
    _offset += 4;
  }

  @override
  void writeUint64(int value) {
    data.buffer.asByteData().setUint64(_offset, value);
    _offset += 8;
  }
}

final class _CountingBinEncoder extends BinEncoder {
  int _count = 0;

  int get count => _count;

  @override
  void writeBytes(Uint8List bytes) {
    _count += bytes.length;
  }

  @override
  void writeUint08(int value) {
    _count++;
  }

  @override
  void writeUint16(int value) {
    _count += 2;
  }

  @override
  void writeUint32(int value) {
    _count += 4;
  }

  @override
  void writeUint64(int value) {
    _count += 8;
  }
}
