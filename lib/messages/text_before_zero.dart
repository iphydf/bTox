import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/message_format.dart';

/// A message's text up to its first zero byte. Some clients put data that
/// isn't text after it.
final class TextBeforeZero implements MessageFormat {
  const TextBeforeZero();

  @override
  String get id => 'text_before_zero';

  @override
  String title(AppLocalizations l10n) => l10n.hideMessageExtras;

  @override
  String description(AppLocalizations l10n) => l10n.hideMessageExtrasHint;

  @override
  String? read(Uint8List bytes) {
    final end = bytes.indexOf(0);
    return end < 0 ? null : plainText(Uint8List.sublistView(bytes, 0, end));
  }
}
