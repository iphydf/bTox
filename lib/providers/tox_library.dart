import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:toxcore/ffi/tox_library.dart';

part 'tox_library.g.dart';

@Riverpod(keepAlive: true)
Future<ToxLibrary> toxFfi(Ref ref) => loadToxLibrary();
