import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:flutter/foundation.dart' show setEquals;

/// A message's bytes as text.
String plainText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// A message's text as it shows. Text stops at a zero byte, so each one shows
/// as `\0`. With [hideAfterZero], what follows the first one shows as its
/// size: `hi\0[12 bytes]`.
String shownText(String text, {required bool hideAfterZero}) {
  final zero = text.indexOf('\u0000');
  if (hideAfterZero && zero >= 0) {
    final rest = utf8.encode(text.substring(zero + 1)).length;
    return '${text.substring(0, zero)}\\0[$rest bytes]';
  }
  return text.replaceAll('\u0000', r'\0');
}

/// How a profile's messages show: in the friends' chats it lists, what
/// follows a zero byte shows as its size.
final class MessageTexts {
  final Set<GraphId> _hidingAfterZero;

  const MessageTexts(this._hidingAfterZero);

  /// As a profile's settings list the chats.
  MessageTexts.hiding(List<String> chats)
    : _hidingAfterZero = {for (final chat in chats) GraphId.fromJson(chat)};

  static const plain = MessageTexts({});

  @override
  bool operator ==(Object other) =>
      other is MessageTexts &&
      setEquals(other._hidingAfterZero, _hidingAfterZero);

  @override
  int get hashCode => Object.hashAllUnordered(_hidingAfterZero);

  /// The text of a message's [bytes] in [chat].
  String read(Uint8List bytes, GraphId chat) => shownText(
    plainText(bytes),
    hideAfterZero: _hidingAfterZero.contains(chat),
  );
}
