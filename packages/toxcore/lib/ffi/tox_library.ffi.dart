import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:toxcore/ffi/generated/toxcore.ffi.dart';

export 'dart:ffi';

export 'package:toxcore/ffi/generated/toxcore.ffi.dart';

/// Elsewhere the app links libtoxcore in.
Future<ToxLibrary> loadToxLibrary() async => ToxLibrary(
  malloc,
  ToxFfi(
    Platform.isAndroid
        ? DynamicLibrary.open('libtoxcore.so')
        : Platform.isWindows
        ? DynamicLibrary.open('libtoxcore.dll')
        : DynamicLibrary.process(),
  ),
);

typedef CChar = Char;

typedef CEnum = UnsignedInt;

final class ToxLibrary {
  final Allocator allocator;
  final ToxFfi ffi;

  const ToxLibrary(this.allocator, this.ffi);
}
