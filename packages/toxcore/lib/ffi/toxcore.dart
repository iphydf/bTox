import 'dart:convert';
import 'dart:typed_data';

import 'package:toxcore/crypto.dart';
import 'package:toxcore/ffi/tox_av.dart';
import 'package:toxcore/ffi/tox_library.dart';
import 'package:toxcore/messagepack.dart';
import 'package:toxcore/tox.dart' as api;
import 'package:toxcore/tox_av.dart' as api;
import 'package:toxcore/tox_events.dart';
import 'package:toxcore/tox_options.dart' as api;

export 'package:toxcore/ffi/tox_library.dart' hide ToxLibrary, loadToxLibrary;

U _handleError<T extends Enum, U>(
  Allocator allocator,
  T Function(int) toEnum,
  U Function(Pointer<CEnum>) callback, [
  String? functionName,
]) {
  return _scoped(allocator.free, allocator<CEnum>(), (err) {
    final result = callback(err);
    if (err.value != 0) {
      throw api.ApiException(toEnum(err.value), functionName);
    }
    return result;
  });
}

U _scoped<T extends NativeType, U>(
  void Function(Pointer<T>) cleanup,
  Pointer<T> ptr,
  U Function(Pointer<T>) f,
) {
  try {
    return f(ptr);
  } finally {
    cleanup(ptr);
  }
}

final class Toxcore extends api.Tox with api.ToxFfiApi {
  @override
  final ToxLibrary lib;

  Pointer<Tox> _pointer;

  /// Calls after [kill] throw, rather than pass toxcore a null Tox.
  @override
  Pointer<Tox> get pointer =>
      _pointer == nullptr ? throw StateError('The Tox was killed') : _pointer;

  factory Toxcore(ToxLibrary lib, api.ToxOptions options) {
    return _scoped(
      lib.ffi.tox_options_free,
      _handleError(
        lib.allocator,
        api.OptionsNewError.fromValue,
        lib.ffi.tox_options_new,
      ),
      (native) {
        options.applyTo(lib, native);
        final ptr = _handleError(
          lib.allocator,
          api.NewError.fromValue,
          (err) => lib.ffi.tox_new(native, err),
        );
        lib.ffi.tox_events_init(ptr);
        return Toxcore._(lib, ptr);
      },
    );
  }

  ToxAvFfi? _av;

  Toxcore._(this.lib, this._pointer);

  @override
  bool get isAlive => _pointer != nullptr;

  @override
  List<Event> iterate() {
    return _handleError(
      lib.allocator,
      api.IterateOptionsNewError.fromValue,
      (optErr) => _scoped(
        lib.ffi.tox_iterate_options_free,
        lib.ffi.tox_iterate_options_new(optErr),
        (options) {
          lib.ffi.tox_iterate_options_set_fail_hard(options, true);
          return _iterate(options);
        },
      ),
    );
  }

  List<Event> _iterate(Pointer<Tox_Iterate_Options> options) {
    return _handleError(lib.allocator, api.EventsIterateError.fromValue, (err) {
      return _scoped(
        lib.ffi.tox_events_free,
        lib.ffi.tox_events_iterate(pointer, options, err),
        (events) {
          final size = lib.ffi.tox_events_bytes_size(events);
          return _scoped(lib.allocator.free, lib.allocator<Uint8>(size), (ptr) {
            if (!lib.ffi.tox_events_get_bytes(events, ptr)) {
              throw Exception('Failed to get events bytes');
            }
            // The events keep views of these bytes, so copy them out of
            // the native buffer we free.
            return unpackEvents(Unpacker(ptr.asTypedList(size).clone()));
          });
        },
      );
    });
  }

  @override
  api.ToxAv startAv() => _av ??= ToxAvFfi(lib, pointer);

  @override
  GroupSecretKey groupSelfGetSecretKey(api.GroupNumber groupNumber) =>
      _native(lib.allocator, (n) {
        final out = n.buffer(GroupSecretKey.kLength);
        _handleError(
          lib.allocator,
          api.GroupSelfQueryError.fromValue,
          (err) => lib.ffi.tox_group_self_get_secret_key(
            pointer,
            groupNumber.value,
            out,
            err,
          ),
          'tox_group_self_get_secret_key',
        );
        return GroupSecretKey(out.asTypedList(GroupSecretKey.kLength).clone());
      });

  @override
  GroupSecretKey? groupGetChatSecretKey(api.GroupNumber groupNumber) =>
      _native(lib.allocator, (n) {
        final out = n.buffer(GroupSecretKey.kLength);
        final err = n.error();
        lib.ffi.tox_group_get_chat_secret_key(
          pointer,
          groupNumber.value,
          out,
          err,
        );
        return switch (err.value) {
          0 => GroupSecretKey(out.asTypedList(GroupSecretKey.kLength).clone()),
          final value
              when value == api.GroupGetChatSecretKeyError.notFounder.value =>
            null,
          final value => throw api.ApiException(
            api.GroupGetChatSecretKeyError.fromValue(value),
            'tox_group_get_chat_secret_key',
          ),
        };
      });

  @override
  api.GroupNumber groupJoinAs(
    GroupChatId chatId,
    GroupSecretKey selfSecretKey,
    GroupSecretKey? chatSecretKey,
    api.GroupPrivacyState privacyState,
    Uint8List name,
    Uint8List password,
    Uint8List? state,
  ) => _native(lib.allocator, (n) {
    final loaded = state == null
        ? nullptr
        : _handleError(
            lib.allocator,
            api.GroupStateLoadError.fromValue,
            (err) => lib.ffi.tox_group_state_load(
              lib.ffi.tox_get_system(pointer),
              n.bytes(state),
              state.length,
              err,
            ),
            'tox_group_state_load',
          );
    try {
      return api.GroupNumber(
        _handleError(
          lib.allocator,
          api.GroupJoinAsError.fromValue,
          (err) => lib.ffi.tox_group_join_as(
            pointer,
            n.bytes(chatId.bytes),
            Tox_Group_Privacy_State.fromValue(privacyState.value),
            n.bytes(selfSecretKey.bytes),
            chatSecretKey == null ? nullptr : n.bytes(chatSecretKey.bytes),
            n.bytes(name),
            name.length,
            n.bytes(password),
            password.length,
            loaded,
            err,
          ),
          'tox_group_join_as',
        ),
      );
    } finally {
      lib.ffi.tox_group_state_free(loaded);
    }
  });

  @override
  Uint8List? groupGetState(api.GroupNumber groupNumber) =>
      _native(lib.allocator, (n) {
        final err = n.error();
        final state = lib.ffi.tox_group_get_state(
          pointer,
          groupNumber.value,
          err,
        );
        if (err.value == api.GroupGetStateError.noState.value) {
          return null;
        }
        if (err.value != 0) {
          throw api.ApiException(
            api.GroupGetStateError.fromValue(err.value),
            'tox_group_get_state',
          );
        }
        try {
          final size = lib.ffi.tox_group_state_bytes_size(state);
          final out = n.buffer(size);
          lib.ffi.tox_group_state_get_bytes(state, out);
          return out.asTypedList(size).clone();
        } finally {
          lib.ffi.tox_group_state_free(state);
        }
      });

  @override
  void kill() {
    _av?.kill();
    _av = null;
    final ptr = pointer;
    _pointer = nullptr;
    lib.ffi.tox_kill(ptr);
  }
}

bool isToxSaveEncrypted(ToxLibrary lib, Uint8List save) =>
    save.length >= lib.ffi.tox_pass_encryption_extra_length() &&
    save.scoped(lib.allocator, (ptr, _) => lib.ffi.tox_is_data_encrypted(ptr));

Uint8List decryptToxSave(ToxLibrary lib, Uint8List save, String passphrase) {
  final plainLength = save.length - lib.ffi.tox_pass_encryption_extra_length();
  return save.scoped(lib.allocator, (savePtr, length) {
    return utf8.encode(passphrase).scoped(lib.allocator, (passPtr, passLength) {
      return _scoped(lib.allocator.free, lib.allocator<Uint8>(plainLength), (
        plain,
      ) {
        _handleError(
          lib.allocator,
          api.DecryptionError.fromValue,
          (err) => lib.ffi.tox_pass_decrypt(
            savePtr,
            length,
            passPtr,
            passLength,
            plain,
            err,
          ),
          'tox_pass_decrypt',
        );
        return plain.asTypedList(plainLength).clone();
      });
    });
  });
}

Uint8List passEncrypt(ToxLibrary lib, Uint8List data, String passphrase) {
  final length = data.length + lib.ffi.tox_pass_encryption_extra_length();
  return data.scoped(lib.allocator, (dataPtr, dataLength) {
    return utf8.encode(passphrase).scoped(lib.allocator, (passPtr, passLength) {
      return _scoped(lib.allocator.free, lib.allocator<Uint8>(length), (
        encrypted,
      ) {
        _handleError(
          lib.allocator,
          api.EncryptionError.fromValue,
          (err) => lib.ffi.tox_pass_encrypt(
            dataPtr,
            dataLength,
            passPtr,
            passLength,
            encrypted,
            err,
          ),
          'tox_pass_encrypt',
        );
        return encrypted.asTypedList(length).clone();
      });
    });
  });
}

/// Native memory for one call, freed together afterwards.
final class _Native {
  final Allocator _allocator;
  final _pointers = <Pointer<NativeType>>[];

  _Native(this._allocator);

  P _add<P extends Pointer<NativeType>>(P pointer) {
    _pointers.add(pointer);
    return pointer;
  }

  Pointer<CEnum> error() => _add(_allocator<CEnum>());

  Pointer<Uint8> buffer(int length) =>
      _add(_allocator<Uint8>(length == 0 ? 1 : length));

  Pointer<Uint8> bytes(List<int> data) {
    final pointer = buffer(data.length);
    pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  Pointer<CChar> string(String value) =>
      bytes(utf8.encode('$value\u0000')).cast();

  void free() => _pointers.forEach(_allocator.free);
}

U _native<U>(Allocator allocator, U Function(_Native) f) {
  final native = _Native(allocator);
  try {
    return f(native);
  } finally {
    native.free();
  }
}

extension on Uint8List {
  Uint8List clone() => Uint8List.fromList(this);

  T scoped<T>(Allocator allocator, T Function(Pointer<Uint8>, int length) f) {
    return _scoped(allocator.free, allocator.allocate<Uint8>(length), (ptr) {
      ptr.asTypedList(length).setAll(0, this);
      return f(ptr, length);
    });
  }
}
