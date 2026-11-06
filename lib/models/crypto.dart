import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:toxcore/bytes.dart';
import 'package:toxcore/crypto.dart';

export 'package:toxcore/crypto.dart';

// The length of a SHA-256 hash, which names events, graphs and heads.
const _hashLength = 32;

final class NospamConverter extends TypeConverter<ToxAddressNospam, int>
    with JsonTypeConverter2<ToxAddressNospam, int, int> {
  const NospamConverter();

  @override
  ToxAddressNospam fromJson(int json) => ToxAddressNospam(json);
  @override
  ToxAddressNospam fromSql(int fromDb) => fromJson(fromDb);
  @override
  int toJson(ToxAddressNospam value) => value.value;
  @override
  int toSql(ToxAddressNospam value) => toJson(value);
}

/// Stores keys and hashes as hex strings.
final class HexConverter<T extends CryptoBytes> extends TypeConverter<T, String>
    with JsonTypeConverter2<T, String, String> {
  final T Function(String) _fromJson;

  const HexConverter(this._fromJson);

  @override
  T fromJson(String json) => _fromJson(json);
  @override
  T fromSql(String fromDb) => fromJson(fromDb);
  @override
  String toJson(T value) => value.toJson();
  @override
  String toSql(T value) => toJson(value);
}

/// A file's bytes, named by their SHA-256.
final class BlobId extends CryptoBytes {
  BlobId(super.bytes);

  factory BlobId.fromJson(String value) =>
      BlobId(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => _hashLength;
}

final class EventId extends CryptoBytes implements Comparable<EventId> {
  EventId(super.bytes);

  factory EventId.of(Uint8List event) =>
      EventId(Uint8List.fromList(sha256.convert(event).bytes));

  factory EventId.fromJson(String value) =>
      EventId(Uint8List.fromList(hex.decode(value)));

  @override
  int get length => _hashLength;

  @override
  int compareTo(EventId other) => compareBytes(bytes, other.bytes);
}

final class GraphId extends CryptoBytes {
  static const kLength = _hashLength;

  GraphId(super.bytes);

  factory GraphId.fromJson(String value) =>
      GraphId(Uint8List.fromList(hex.decode(value)));

  factory GraphId._of(List<List<int>> parts) => GraphId(
    Uint8List.fromList(sha256.convert(parts.expand((p) => p).toList()).bytes),
  );

  factory GraphId.account(PublicKey account) =>
      GraphId._of([utf8.encode('account'), account.bytes]);

  factory GraphId.friend(PublicKey account, PublicKey friend) =>
      GraphId._of([utf8.encode('friend'), account.bytes, friend.bytes]);

  factory GraphId.group(GroupChatId id) =>
      GraphId._of([utf8.encode('group'), id.bytes]);

  factory GraphId.conference(ConferenceId id) =>
      GraphId._of([utf8.encode('conference'), id.bytes]);

  @override
  int get length => _hashLength;
}

/// Equal on two devices exactly when they have the same heads.
final class HeadsDigest extends CryptoBytes {
  HeadsDigest(super.bytes);

  factory HeadsDigest.of(Iterable<EventId> heads) {
    final sorted = heads.map((head) => head.bytes).toList()
      ..sort(compareBytes);
    return HeadsDigest(
      Uint8List.fromList(
        sha256.convert(sorted.expand((b) => b).toList()).bytes,
      ),
    );
  }

  @override
  int get length => _hashLength;
}
