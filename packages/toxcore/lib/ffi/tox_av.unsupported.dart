import 'package:toxcore/ffi/tox_library.dart';
import 'package:toxcore/tox_av.dart' as api;

/// Browsers can't take toxav's callbacks.
abstract final class ToxAvFfi extends api.ToxAv {
  factory ToxAvFfi(ToxLibrary lib, Pointer<Tox> tox) =>
      throw UnsupportedError('No calls on the web');

  void kill();
}
