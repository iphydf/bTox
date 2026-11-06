import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/message_format.dart';

/// A message format only tests know: "text#rest" reads as the text before
/// the last "#".
final class FakeMessageFormat implements MessageFormat {
  const FakeMessageFormat();

  static Uint8List encode(String text, String rest) =>
      utf8.encode('$text#$rest');

  @override
  String get id => 'fake';

  @override
  String title(AppLocalizations l10n) => 'Fake';

  @override
  String description(AppLocalizations l10n) => 'Reads text#rest';

  @override
  String? read(Uint8List bytes) {
    final message = utf8.decode(bytes, allowMalformed: true);
    final end = message.lastIndexOf('#');
    return end < 0 ? null : message.substring(0, end);
  }
}

const withFakeFormat = MessageFormats([FakeMessageFormat()]);
