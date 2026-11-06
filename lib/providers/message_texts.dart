import 'package:btox/messages/message_text.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/profiles.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'message_texts.g.dart';

/// How a profile's messages show.
@riverpod
MessageTexts messageTexts(Ref ref, Id<Profiles> id) => MessageTexts.hiding(
  ref.watch(
    profileProvider(
      id,
    ).select((profile) => profile.value?.settings.hiddenAfterZero ?? []),
  ),
);
