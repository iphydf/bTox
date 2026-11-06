import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// A message's bytes as text, in no format.
String plainText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// A way some clients put more than text into a friend's message. Each is a
/// plugin, on unless the profile turns it off, which then shows the bytes as
/// text.
abstract interface class MessageFormat {
  /// Kept in the profile's settings while it's off.
  String get id;

  String title(AppLocalizations l10n);

  String description(AppLocalizations l10n);

  /// The text in [bytes], or null if they aren't in this format.
  String? read(Uint8List bytes);
}

/// The message formats a profile has on.
final class MessageFormats {
  final List<MessageFormat> _formats;

  const MessageFormats(this._formats);

  static const none = MessageFormats([]);

  @override
  bool operator ==(Object other) =>
      other is MessageFormats && listEquals(other._formats, _formats);

  @override
  int get hashCode => Object.hashAll(_formats);

  /// The text in a message's [bytes], read by the first format they're in.
  /// Messages in groups, and those in no format, are UTF-8 text.
  String read(Uint8List bytes, {required bool friend}) {
    if (friend) {
      for (final format in _formats) {
        if (format.read(bytes) case final text?) {
          return text;
        }
      }
    }
    return plainText(bytes);
  }
}
