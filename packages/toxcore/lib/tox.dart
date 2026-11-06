import 'dart:typed_data';

import 'package:toxcore/crypto.dart';
import 'package:toxcore/tox_api.dart';
import 'package:toxcore/tox_av.dart';
import 'package:toxcore/tox_enums.dart';
import 'package:toxcore/tox_events.dart';
import 'package:toxcore/tox_ids.dart';

export 'package:toxcore/tox_api.dart';
export 'package:toxcore/tox_enums.dart';
export 'package:toxcore/tox_errors.dart';
export 'package:toxcore/tox_ids.dart';

/// A running Tox: toxcore's functions, plus its events and its end.
abstract class Tox implements ToxApi {
  const Tox();

  bool get isAlive;

  List<Event> iterate();

  /// Started on first use. It ends with this Tox.
  ToxAv startAv();

  /// Our secret key in a group, which makes our public key in it.
  GroupSecretKey groupSelfGetSecretKey(GroupNumber groupNumber);

  /// The group's secret key, or null if we're not its founder.
  GroupSecretKey? groupGetChatSecretKey(GroupNumber groupNumber);

  /// Joins a group using an existing [selfSecretKey], and as its founder with
  /// its [chatSecretKey]. With a [state], the group has its settings
  /// immediately. Otherwise, it receives them from a peer.
  GroupNumber groupJoinAs(
    GroupChatId chatId,
    GroupSecretKey selfSecretKey,
    GroupSecretKey? chatSecretKey,
    GroupPrivacyState privacyState,
    Uint8List name,
    Uint8List password,
    Uint8List? state,
  );

  /// The state of the group, or null if it has no settings yet.
  Uint8List? groupGetState(GroupNumber groupNumber);

  void kill();
}

/// Thrown by [Tox.iterate].
enum IterateOptionsNewError {
  malloc(1);

  final int value;

  const IterateOptionsNewError(this.value);

  static IterateOptionsNewError fromValue(int value) => switch (value) {
    1 => malloc,
    _ => throw ArgumentError.value(value, 'IterateOptionsNewError'),
  };
}

/// Thrown by [Tox.groupGetChatSecretKey].
enum GroupGetChatSecretKeyError {
  groupNotFound(1),
  notFounder(2);

  final int value;

  const GroupGetChatSecretKeyError(this.value);

  static GroupGetChatSecretKeyError fromValue(int value) => switch (value) {
    1 => groupNotFound,
    2 => notFounder,
    _ => throw ArgumentError.value(value, 'GroupGetChatSecretKeyError'),
  };
}

/// Thrown by [Tox.groupJoinAs].
enum GroupJoinAsError {
  init(1),
  duplicate(2),
  empty(3),
  tooLong(4),
  password(5),
  badState(6),
  badChatSecretKey(7),
  core(8);

  final int value;

  const GroupJoinAsError(this.value);

  static GroupJoinAsError fromValue(int value) => switch (value) {
    1 => init,
    2 => duplicate,
    3 => empty,
    4 => tooLong,
    5 => password,
    6 => badState,
    7 => badChatSecretKey,
    8 => core,
    _ => throw ArgumentError.value(value, 'GroupJoinAsError'),
  };
}

/// Thrown by [Tox.groupGetState].
enum GroupGetStateError {
  groupNotFound(1),
  noState(2),
  malloc(3);

  final int value;

  const GroupGetStateError(this.value);

  static GroupGetStateError fromValue(int value) => switch (value) {
    1 => groupNotFound,
    2 => noState,
    3 => malloc,
    _ => throw ArgumentError.value(value, 'GroupGetStateError'),
  };
}

/// Thrown by [Tox.groupJoinAs] for a state that isn't valid.
enum GroupStateLoadError {
  malloc(1),
  badState(2);

  final int value;

  const GroupStateLoadError(this.value);

  static GroupStateLoadError fromValue(int value) => switch (value) {
    1 => malloc,
    2 => badState,
    _ => throw ArgumentError.value(value, 'GroupStateLoadError'),
  };
}

abstract interface class ToxFiles {
  void chunk(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    Uint8List data,
  );
  void requested(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    int length,
  );
  void controlled(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileControl control,
  );
}
