import 'dart:async';
import 'dart:convert';

import 'package:btox/db/database.steps.dart';
import 'package:btox/messages/message_text.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:drift/drift.dart';
import 'package:toxcore/messagepack.dart';
import 'package:toxcore/tox.dart';
import 'package:toxcore/tox_constants.dart';

export 'package:drift/drift.dart' show Value;

part 'database.drift.dart';

// Within SQLite's limit on variables in one statement.
const _idsPerStatement = 500;

@DriftDatabase(
  tables: [
    AppSettings,
    Avatars,
    ChatDrafts,
    DeletedChats,
    DeliveredParts,
    GroupMemberships,
    Intents,
    LinkedNotified,
    LiveFacts,
    ChatReads,
    Profiles,
    SyncEvents,
    Transfers,
  ],
)
final class Database extends _$Database {
  Database(super.e);

  // Bump with every schema change, then run `tools/prepare` and add the
  // step from the last version to [migration].
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      // The node list is built in. A v1 from before chat saves and delivered
      // parts doesn't have their tables yet.
      from1To2: (m, schema) async {
        await m.deleteTable('cached_bootstrap_nodes');
        await m.createTable(schema.chatSaves);
        await m.createTable(schema.deliveredParts);
      },
      // Groups are kept as the keys Tox joins them with again, not as
      // toxcore's save of them.
      from2To3: (m, schema) async {
        await m.createTable(schema.groupMemberships);
        for (final row in await customSelect(
          "SELECT profile_id, state FROM chat_saves WHERE kind = 'group'",
        ).get()) {
          if (_keptGroup(row.read<Uint8List>('state')) case final kept?) {
            await customInsert(
              'INSERT INTO group_memberships (profile_id, chat_id, '
              'self_secret_key, chat_secret_key, privacy, password, endpoints) '
              'VALUES (?, ?, ?, ?, ?, ?, ?)',
              variables: [
                Variable<int>(row.read<int>('profile_id')),
                Variable<String>(kept.chatId.toJson()),
                Variable<String>(kept.self.toJson()),
                Variable<String>(kept.chat?.toJson()),
                Variable<String>(kept.privacy.name),
                Variable<String>(kept.password),
                const Variable<String>('[]'),
              ],
            );
          }
        }
        await m.deleteTable('chat_saves');
      },
      // A group is found through our friends again, not at the endpoints of
      // its peers.
      from3To4: (m, schema) async {
        await m.dropColumn(schema.groupMemberships, 'endpoints');
        await m.addColumn(
          schema.groupMemberships,
          schema.groupMemberships.state,
        );
      },
    ),
  );

  // Events never change, so each is decoded once.
  final _decoded = <EventId, SyncEvent?>{};
  // Each chat's latest events of one rank, with how many events it had, and
  // the one it showed last: the same while it has no others.
  final _lastOfTied = <GraphId, (Set<EventId>, int, EventId)>{};

  Future<Id<Profiles>> addProfile(ProfilesCompanion entry) async =>
      Id(await into(profiles).insert(entry));

  /// Returns the paths of the profile's files, for the caller to delete.
  Future<List<String>> deleteProfile(Id<Profiles> id) => transaction(() async {
    // What belongs to the profile goes first, as it refers to the profile.
    final files = await _deleteWhere({'profile_id': Variable<int>(id.value)});
    await (delete(profiles)..where((p) => p.id.equals(id.value))).go();
    return files;
  });

  /// Deletes the rows with these [values] from every table that has their
  /// columns, apart from the [kept] ones, and returns the paths of the files
  /// whose transfers or drafts went.
  Future<List<String>> _deleteWhere(
    Map<String, Variable> values, {
    Set<TableInfo> kept = const {},
  }) async {
    final where = values.keys.map((column) => '$column = ?').join(' AND ');
    final files = [
      for (final row in await customSelect(
        'SELECT path FROM "${transfers.actualTableName}" WHERE $where',
        variables: [...values.values],
        readsFrom: {transfers},
      ).get())
        row.read<String>('path'),
      for (final row in await customSelect(
        'SELECT attachments FROM "${chatDrafts.actualTableName}" '
        'WHERE $where',
        variables: [...values.values],
        readsFrom: {chatDrafts},
      ).get())
        for (final content in const ContentListConverter().fromSql(
          row.read<String>('attachments'),
        ))
          if (content case FileContent(:final path)) path,
    ];
    for (final table in allTables) {
      if (!kept.contains(table) &&
          values.keys.every(table.columnsByName.containsKey)) {
        await customUpdate(
          'DELETE FROM "${table.actualTableName}" WHERE $where',
          variables: [...values.values],
          updates: {table},
          updateKind: UpdateKind.delete,
        );
      }
    }
    return files;
  }

  Future<void> addSyncEvents(
    Id<Profiles> profileId,
    Iterable<NewEvent> events,
  ) => batch((batch) {
    batch.insertAll(syncEvents, [
      for (final (id, event, bytes) in events)
        SyncEventsCompanion.insert(
          profileId: profileId,
          id: id,
          graph: event.graph,
          rank: event.rank,
          received: isIncoming(event.content),
          shown: Value(entryOf(id, event, MessageTexts.plain) != null),
          bytes: bytes,
        ),
    ], mode: InsertMode.insertOrIgnore);
  });

  /// The latest entry of each chat, as the chat shows it.
  Stream<Map<GraphId, ChatEntry>> watchLatestEntries(
    Id<Profiles> profileId,
    MessageTexts texts,
  ) =>
      customSelect(
        'SELECT e.id, e.bytes FROM sync_events e JOIN ('
        'SELECT graph, MAX(rank) AS rank FROM sync_events '
        'WHERE profile_id = ?1 AND shown GROUP BY graph'
        ') latest ON e.graph = latest.graph AND e.rank = latest.rank '
        'WHERE e.profile_id = ?1 AND e.shown',
        variables: [Variable<int>(profileId.value)],
        readsFrom: {syncEvents},
      ).watch().asyncMap((rows) async {
        final candidates = <GraphId, Map<EventId, ChatEntry>>{};
        for (final row in rows) {
          final id = EventId.fromJson(row.read<String>('id'));
          final event = _decoded[id] ??= _readable(
            row.read<Uint8List>('bytes'),
          );
          if (event case final event?) {
            if (entryOf(id, event, texts) case final entry?) {
              (candidates[event.graph] ??= {})[id] = entry;
            }
          }
        }
        final latest = <GraphId, (EventId, ChatEntry)>{};
        for (final MapEntry(key: graph, value: entries) in candidates.entries) {
          var last = entries.keys.last;
          if (entries.length > 1) {
            final ids = entries.keys.toSet();
            final count = await _countIn(profileId, graph);
            last = switch (_lastOfTied[graph]) {
              (final tied, final events, final known)
                  when events == count &&
                      tied.length == ids.length &&
                      tied.containsAll(ids) =>
                known,
              // Of events of the same rank, the one the chat shows last: it
              // also orders them by when they came after their parents.
              _ =>
                ChatLog(texts)
                    .update(await _syncEventsIn(profileId, graph))
                    .map((e) => e.event)
                    .lastWhere(entries.containsKey, orElse: () => last),
            };
            _lastOfTied[graph] = (ids, count, last);
          }
          latest[graph] = (last, entries[last]!);
        }
        return {
          for (final MapEntry(:key, value: (id, entry)) in latest.entries)
            key: switch (entry.content) {
              CallContent(ended: false) => await _callAsEnded(
                profileId,
                key,
                id,
                entry,
              ),
              _ => entry,
            },
        };
      });

  /// If it has ended: its end isn't an entry, so it's later than the latest.
  Future<ChatEntry> _callAsEnded(
    Id<Profiles> profileId,
    GraphId graph,
    EventId call,
    ChatEntry entry,
  ) async {
    final rows = await customSelect(
      'SELECT id, bytes FROM sync_events WHERE profile_id = ? AND graph = ? '
      'AND rank > ? AND NOT shown',
      variables: [
        Variable<int>(profileId.value),
        Variable(graph.toJson()),
        Variable<int>(_decoded[call]?.rank ?? 0),
      ],
      readsFrom: {syncEvents},
    ).get();
    for (final row in rows) {
      final id = EventId.fromJson(row.read<String>('id'));
      final event = _decoded[id] ??= _readable(row.read<Uint8List>('bytes'));
      if (event?.content case final CallEnded end when end.call == call) {
        return endedAs(entry, end);
      }
    }
    return entry;
  }

  /// Signs the profile in and shows it.
  Future<void> signIn(Id<Profiles> id) => transaction(() async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(true)),
    );
    await updateAppSettings(AppSettingsCompanion(currentProfile: Value(id)));
  });

  Future<void> signOut(Id<Profiles> id) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(false)),
    );
  }

  Future<void> updateAppSettings(AppSettingsCompanion settings) async {
    await into(appSettings).insert(
      settings.copyWith(id: const Value(0)),
      onConflict: DoUpdate((_) => settings),
    );
  }

  /// Changes the settings as they are now, so quick changes don't undo
  /// each other.
  Future<void> updateProfileSettings(
    Id<Profiles> id,
    ProfileSettings Function(ProfileSettings) change,
  ) => transaction(() async {
    final row = profiles.id.equals(id.value);
    final current = await (select(profiles)..where((_) => row)).getSingle();
    await (update(profiles)..where((_) => row)).write(
      ProfilesCompanion(settings: Value(change(current.settings))),
    );
  });

  Future<List<Uint8List>> getSyncEvents(Id<Profiles> profileId) async =>
      (selectOnly(syncEvents)
            ..addColumns([syncEvents.bytes])
            ..where(syncEvents.profileId.equals(profileId.value)))
          .map((row) => row.read(syncEvents.bytes)!)
          .get();

  /// Forgets events this version can't read, which then sync again in a form
  /// it can, and the read positions that name them.
  Future<void> dropSyncEvents(
    Id<Profiles> profileId,
    List<EventId> ids,
  ) => transaction(() async {
    for (var i = 0; i < ids.length; i += _idsPerStatement) {
      final batch = ids.skip(i).take(_idsPerStatement);
      await (delete(syncEvents)..where(
            (e) => e.profileId.equals(profileId.value) & e.id.isInValues(batch),
          ))
          .go();
      await (delete(chatReads)..where(
            (r) =>
                r.profileId.equals(profileId.value) & r.event.isInValues(batch),
          ))
          .go();
    }
  });

  /// Long messages are split over several events.
  Future<void> addSend(
    Id<Profiles> profileId,
    GraphId graph,
    String message, {
    PublicKey? privately,
    MessageType kind = MessageType.normal,
  }) => batch(
    (batch) => batch.insertAll(intents, [
      for (final part in splitMessage(utf8.encode(message), maxSendBytes))
        IntentsCompanion.insert(
          profileId: profileId,
          graph: Value(graph),
          // The service fills in our name.
          content: switch (privately) {
            final to? => SendPrivately(
              to: to,
              sender: '',
              message: part,
              kind: kind,
            ),
            null => Send(sender: '', message: part, kind: kind),
          },
        ),
    ]),
  );

  Future<void> addFileSend(
    Id<Profiles> profileId,
    GraphId graph,
    FileContent file,
  ) => addTransfer(
    TransfersCompanion.insert(
      profileId: profileId,
      graph: graph,
      incoming: false,
      name: file.name,
      size: file.size,
      path: file.path,
      state: FileState.active,
    ),
  );

  Future<Map<GraphId, int>> getLinkedNotified(Id<Profiles> profileId) async => {
    for (final row in await (select(
      linkedNotified,
    )..where((n) => n.profileId.equals(profileId.value))).get())
      row.graph: row.rank,
  };

  Future<void> setLinkedNotified(
    Id<Profiles> profileId,
    GraphId graph,
    int rank,
  ) async {
    await into(linkedNotified).insertOnConflictUpdate(
      LinkedNotifiedCompanion.insert(
        profileId: profileId,
        graph: graph,
        rank: rank,
      ),
    );
  }

  Future<void> setRead(
    Id<Profiles> profileId,
    GraphId graph,
    (int, EventId) upTo,
  ) async {
    await into(chatReads).insertOnConflictUpdate(
      ChatReadsCompanion.insert(
        profileId: profileId,
        graph: graph,
        event: upTo.$2,
        rank: upTo.$1,
      ),
    );
  }

  Stream<List<ChatRead>> watchReads(Id<Profiles> profileId) => (select(
    chatReads,
  )..where((r) => r.profileId.equals(profileId.value))).watch();

  SimpleSelectStatement<$AvatarsTable, StoredAvatar> _avatar(
    Id<Profiles> profileId,
    BlobId blob,
  ) => select(avatars)
    ..where(
      (a) => a.profileId.equals(profileId.value) & a.blobId.equalsValue(blob),
    );

  Future<Uint8List?> getAvatar(Id<Profiles> profileId, BlobId blob) =>
      _avatar(profileId, blob).map((a) => a.bytes).getSingleOrNull();

  Future<Set<BlobId>> avatarsHeld(Id<Profiles> profileId) async =>
      (await (selectOnly(avatars)
                ..addColumns([avatars.blobId])
                ..where(avatars.profileId.equals(profileId.value)))
              .map((row) => row.readWithConverter(avatars.blobId)!)
              .get())
          .toSet();

  Future<void> deleteAvatars(Id<Profiles> profileId, Set<BlobId> blobs) =>
      transaction(() async {
        for (var i = 0; i < blobs.length; i += _idsPerStatement) {
          final batch = blobs.skip(i).take(_idsPerStatement);
          await (delete(avatars)..where(
                (a) =>
                    a.profileId.equals(profileId.value) &
                    a.blobId.isInValues(batch),
              ))
              .go();
        }
      });

  Stream<Uint8List?> watchAvatar(Id<Profiles> profileId, BlobId blob) =>
      _avatar(profileId, blob).map((a) => a.bytes).watchSingleOrNull();

  Future<void> setAvatar(
    Id<Profiles> profileId,
    BlobId blob,
    Uint8List bytes,
  ) async {
    await into(avatars).insertOnConflictUpdate(
      AvatarsCompanion.insert(profileId: profileId, blobId: blob, bytes: bytes),
    );
  }

  Future<StoredDraft?> getDraft(Id<Profiles> profileId, GraphId graph) =>
      (select(chatDrafts)..where(
            (d) =>
                d.profileId.equals(profileId.value) &
                d.graph.equalsValue(graph),
          ))
          .getSingleOrNull();

  Stream<Map<GraphId, StoredDraft>> watchDrafts(Id<Profiles> profileId) =>
      (select(chatDrafts)..where((d) => d.profileId.equals(profileId.value)))
          .watch()
          .map((drafts) => {for (final draft in drafts) draft.graph: draft});

  Future<void> setDraft(StoredDraft draft) async {
    await into(chatDrafts).insertOnConflictUpdate(draft);
  }

  Future<void> clearDraft(Id<Profiles> profileId, GraphId graph) async {
    await (delete(chatDrafts)..where(
          (d) =>
              d.profileId.equals(profileId.value) & d.graph.equalsValue(graph),
        ))
        .go();
  }

  /// The ranks of others' messages and files, by conversation.
  Stream<Map<GraphId, List<int>>> watchReceivedRanks(Id<Profiles> profileId) {
    var ranks = <GraphId, List<int>>{};
    return _addedEvents('profile_id = ? AND received', [
      Variable<int>(profileId.value),
    ]).map((added) {
      if (added.all) {
        ranks = {};
      }
      for (final (_, event) in added.events) {
        (ranks[event.graph] ??= []).add(event.rank);
      }
      return {
        for (final MapEntry(:key, :value) in ranks.entries) key: [...value],
      };
    });
  }

  Future<void> addIntent(
    Id<Profiles> profileId,
    EventContent content, {
    GraphId? graph,
    bool deleteChat = false,
  }) async {
    await intents.insertOne(
      IntentsCompanion.insert(
        profileId: profileId,
        graph: Value(graph),
        content: content,
        deleteChat: Value(deleteChat),
      ),
    );
  }

  Future<void> showApart(
    Id<Profiles> profileId,
    GraphId chat,
    Map<ChatId, AccountMerge> merges,
  ) async {
    for (final MapEntry(key: other, value: merge) in merges.entries) {
      if (merge.into.graph == chat) {
        await addIntent(
          profileId,
          MergeChat(
            chat: other,
            bot: merge.bot,
            into: merge.into,
            intoBot: merge.intoBot,
            merged: false,
          ),
        );
      }
    }
  }

  Stream<List<StoredIntent>> watchIntents(Id<Profiles> profileId) =>
      (select(intents)
            ..where((i) => i.profileId.equals(profileId.value))
            ..orderBy([(i) => OrderingTerm(expression: i.id)]))
          .watch();

  /// Returns the [deleted] chat's files.
  Future<List<String>> writeIntent(
    StoredIntent intent,
    NewEvent event, {
    (GraphId, int)? deleted,
  }) => transaction(() async {
    await addSyncEvents(intent.profileId, [event]);
    await intents.deleteOne(intent);
    return deleted == null ? const [] : _deleteChat(intent.profileId, deleted);
  });

  /// Deletes a [chat]'s rows, remembering the rank its next event takes, and
  /// returns the paths of its files.
  Future<List<String>> _deleteChat(
    Id<Profiles> profileId,
    (GraphId, int) chat,
  ) async {
    final (graph, rank) = chat;
    final files = await _deleteWhere(
      {
        'profile_id': Variable<int>(profileId.value),
        'graph': Variable<String>(graph.toJson()),
      },
      kept: {deletedChats},
    );
    await into(deletedChats).insertOnConflictUpdate(
      DeletedChatsCompanion.insert(
        profileId: profileId,
        graph: graph,
        rank: rank,
      ),
    );
    return files;
  }

  /// The chats deleted on this device, by the rank their next event takes.
  Future<Map<GraphId, int>> getDeletedChats(Id<Profiles> profileId) async => {
    for (final row in await (select(
      deletedChats,
    )..where((c) => c.profileId.equals(profileId.value))).get())
      row.graph: row.rank,
  };

  Future<List<GroupMembership>> getGroupMemberships(Id<Profiles> profileId) =>
      (select(
        groupMemberships,
      )..where((g) => g.profileId.equals(profileId.value))).get();

  Future<void> saveGroupMembership(GroupMembershipsCompanion membership) =>
      into(groupMemberships).insertOnConflictUpdate(membership);

  Future<void> forgetGroupMembership(
    Id<Profiles> profileId,
    GroupChatId chatId,
  ) =>
      (delete(groupMemberships)..where(
            (g) =>
                g.profileId.equals(profileId.value) &
                g.chatId.equals(
                  const HexConverter(GroupChatId.fromJson).toSql(chatId),
                ),
          ))
          .go();

  Future<Map<EventId, int>> getDeliveredParts(Id<Profiles> profileId) async => {
    for (final row in await (select(
      deliveredParts,
    )..where((d) => d.profileId.equals(profileId.value))).get())
      row.event: row.parts,
  };

  Future<void> setDeliveredParts(
    Id<Profiles> profileId,
    EventId event,
    int parts,
  ) => into(deliveredParts).insertOnConflictUpdate(
    DeliveredPartsCompanion.insert(
      profileId: profileId,
      event: event,
      parts: parts,
    ),
  );

  Future<void> forgetDeliveredParts(Id<Profiles> profileId, EventId event) =>
      (delete(deliveredParts)..where(
            (d) =>
                d.profileId.equals(profileId.value) &
                d.event.equals(
                  const HexConverter(EventId.fromJson).toSql(event),
                ),
          ))
          .go();

  Future<Id<Transfers>> addTransfer(TransfersCompanion entry) async =>
      Id(await into(transfers).insert(entry));

  /// The latest file from a friend in [graph] under [fileId], of [size],
  /// that stopped before it arrived whole, to go on with it. One cancelled
  /// or declined is offered again as a new one.
  Future<Transfer?> unfinishedTransfer(
    Id<Profiles> profileId,
    GraphId graph,
    FileId fileId,
    int size,
  ) =>
      (select(transfers)
            ..where(
              (t) =>
                  t.profileId.equals(profileId.value) &
                  t.graph.equalsValue(graph) &
                  t.incoming &
                  t.fileId.equalsValue(fileId) &
                  t.size.equals(size) &
                  t.state.isNotInValues([FileState.done, FileState.cancelled]),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  Stream<List<Transfer>> watchTransfers(Id<Profiles> profileId) =>
      (select(transfers)
            ..where((t) => t.profileId.equals(profileId.value))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .watch();

  /// Saves [event], which started [transfer], with the blob it names.
  Future<void> writeTransferEvent(
    Id<Transfers> transfer,
    NewEvent event, {
    BlobId? blob,
  }) => transaction(() async {
    final row = await (select(
      transfers,
    )..where((t) => t.id.equals(transfer.value))).getSingle();
    await addSyncEvents(row.profileId, [event]);
    await (update(transfers)..where((t) => t.id.equals(transfer.value))).write(
      TransfersCompanion(
        event: Value(event.$1),
        blobId: Value.absentIfNull(blob),
      ),
    );
  });

  /// Fetches a linked account's [file], which [event] started, into [path]
  /// from the home device, unless it's fetched already.
  Future<void> fetchFile(
    Id<Profiles> profileId,
    GraphId graph,
    EventId event,
    FileContent file,
    BlobId blob,
    String path,
  ) => transaction(() async {
    final fetched =
        await (select(transfers)..where(
              (t) =>
                  t.profileId.equals(profileId.value) &
                  t.event.equalsValue(event),
            ))
            .get();
    if (fetched.isEmpty) {
      await addTransfer(
        TransfersCompanion.insert(
          profileId: profileId,
          graph: graph,
          event: Value(event),
          incoming: true,
          name: file.name,
          size: file.size,
          path: path,
          state: FileState.active,
          blobId: Value(blob),
        ),
      );
    }
  });

  Future<void> setTransferState(
    Id<Transfers> id,
    FileState state, {
    int? transferred,
  }) async {
    await (update(transfers)..where((t) => t.id.equals(id.value))).write(
      TransfersCompanion(
        state: Value(state),
        transferred: Value.absentIfNull(transferred),
      ),
    );
  }

  /// Accepts a file offered here, or declines one not yet ended, unless it
  /// ended meanwhile.
  Future<void> answerTransfer(Id<Transfers> id, {required bool accept}) async {
    await (update(transfers)..where(
          (t) =>
              t.id.equals(id.value) &
              t.state.isInValues([
                FileState.offered,
                if (!accept) ...[FileState.active, FileState.paused],
              ]),
        ))
        .write(
          TransfersCompanion(
            state: Value(accept ? FileState.active : FileState.cancelled),
          ),
        );
  }

  /// From the start, as cancelled files can't resume.
  Future<void> sendTransferAgain(Id<Transfers> id) async {
    await (update(transfers)..where(
          (t) =>
              t.id.equals(id.value) &
              t.incoming.not() &
              t.state.equalsValue(FileState.cancelled),
        ))
        .write(
          const TransfersCompanion(
            state: Value(FileState.active),
            transferred: Value(0),
          ),
        );
  }

  Future<void> setTransferred(Id<Transfers> id, int transferred) async {
    await (update(transfers)..where((t) => t.id.equals(id.value))).write(
      TransfersCompanion(transferred: Value(transferred)),
    );
  }

  Future<void> clearPairingMessage(Id<Profiles> id) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      const ProfilesCompanion(pairingMessage: Value(null)),
    );
  }

  Future<void> clearLiveFacts(Id<Profiles> profileId) async {
    await (delete(
      liveFacts,
    )..where((f) => f.profileId.equals(profileId.value))).go();
  }

  /// Takes in live facts as [Facts.update] does. With [all], they're all
  /// there are.
  Future<void> updateLiveFacts(
    Id<Profiles> profileId,
    Iterable<Fact> facts, {
    bool all = false,
  }) => transaction(() async {
    if (all) {
      await clearLiveFacts(profileId);
    }
    for (final (subject, value) in facts) {
      // A newer home device's, which shows nothing here.
      if (value is UnknownValue) {
        continue;
      }
      final key = encodeSubject(subject);
      if (value == const FactValue.present(false)) {
        await (delete(liveFacts)..where(
              (f) =>
                  f.profileId.equals(profileId.value) & f.subject.equals(key),
            ))
            .go();
      } else {
        await into(liveFacts).insertOnConflictUpdate(
          LiveFactsCompanion.insert(
            profileId: profileId,
            subject: key,
            kind: value.kind,
            fact: encodeFact(subject, value).encode(),
          ),
        );
      }
    }
  });

  Stream<AppSetting> watchAppSettings() =>
      select(appSettings).watchSingleOrNull().map(
        (settings) =>
            settings ??
            const AppSetting(
              id: 0,
              stayOnline: true,
              autoAcceptFileSize: defaultAutoAcceptFileSize,
            ),
      );

  Stream<Facts> watchLiveFacts(Id<Profiles> id) =>
      (select(liveFacts)..where((f) => f.profileId.equals(id.value)))
          .watch()
          .map((rows) => Facts.of(rows.map((row) => decodeFact(row.fact))));

  Stream<List<(EventId, SyncEvent)>> watchSyncEvents(
    Id<Profiles> id,
    GraphId graph,
  ) {
    var events = const <(EventId, SyncEvent)>[];
    return _addedEvents('profile_id = ? AND graph = ?', [
      Variable<int>(id.value),
      Variable<String>(graph.toJson()),
    ]).map(
      (added) =>
          events = added.all ? added.events : [...events, ...added.events],
    );
  }

  Stream<List<(EventId, SyncEvent)>> watchCalls(Id<Profiles> id) {
    bool isCall((EventId, SyncEvent) e) =>
        e.$2.content is Call || e.$2.content is CallEnded;
    var calls = const <(EventId, SyncEvent)>[];
    return _addedEvents('profile_id = ?', [
      Variable<int>(id.value),
    ]).where((added) => added.all || added.events.any(isCall)).map((added) {
      final more = added.events.where(isCall);
      return calls = added.all ? [...more] : [...calls, ...more];
    });
  }

  /// The readable events [where] picks, each read from the database once:
  /// first all of them, then those added since, in the order they were.
  /// Deleting events starts over with all.
  Stream<({bool all, List<(EventId, SyncEvent)> events})> _addedEvents(
    String where,
    List<Variable> variables,
  ) {
    late final StreamController<({bool all, List<(EventId, SyncEvent)> events})>
    controller;
    StreamSubscription<Set<TableUpdate>>? updates;
    var last = 0;
    var fetching = Future<void>.value();
    void fetch({required bool all}) {
      fetching = fetching
          .then((_) async {
            final rows = await customSelect(
              'SELECT rowid, id, bytes FROM sync_events '
              'WHERE $where AND rowid > ? ORDER BY rowid',
              variables: [...variables, Variable<int>(all ? 0 : last)],
              readsFrom: {syncEvents},
            ).get();
            if (rows.isNotEmpty) {
              last = rows.last.read<int>('rowid');
            } else if (all) {
              // Rows deleted from the end leave their rowids to new ones.
              last = 0;
            }
            if (all || rows.isNotEmpty) {
              controller.add((
                all: all,
                events: [for (final row in rows) ?_decodedRow(row)],
              ));
            }
          })
          .catchError(controller.addError);
    }

    controller = StreamController(
      onListen: () {
        // Listened to first, so nothing added meanwhile is missed.
        updates = tableUpdates(TableUpdateQuery.onTable(syncEvents)).listen(
          (changes) => fetch(
            all: changes.any(
              (change) =>
                  change.kind != UpdateKind.insert &&
                  change.kind != UpdateKind.update,
            ),
          ),
        );
        fetch(all: true);
      },
      onCancel: () => updates?.cancel(),
    );
    return controller.stream;
  }

  Future<int> _countIn(Id<Profiles> id, GraphId graph) async =>
      (await customSelect(
        'SELECT COUNT(*) AS count FROM sync_events '
        'WHERE profile_id = ? AND graph = ?',
        variables: [Variable<int>(id.value), Variable<String>(graph.toJson())],
        readsFrom: {syncEvents},
      ).getSingle()).read<int>('count');

  Future<List<(EventId, SyncEvent)>> _syncEventsIn(
    Id<Profiles> id,
    GraphId graph,
  ) async => [
    for (final row in await customSelect(
      'SELECT id, bytes FROM sync_events WHERE profile_id = ? AND graph = ?',
      variables: [Variable<int>(id.value), Variable<String>(graph.toJson())],
      readsFrom: {syncEvents},
    ).get())
      ?_decodedRow(row),
  ];

  (EventId, SyncEvent)? _decodedRow(QueryRow row) {
    final id = EventId.fromJson(row.read<String>('id'));
    return switch (_decoded[id] ??= _readable(row.read<Uint8List>('bytes'))) {
      final event? => (id, event),
      null => null,
    };
  }

  Stream<Profile> watchProfile(Id<Profiles> id) =>
      (select(profiles)..where((p) => p.id.equals(id.value))).watchSingle();

  Stream<List<Profile>> watchProfiles() => select(profiles).watch();
}

/// Null for an event this version can't read, which the background service
/// drops to sync again.
SyncEvent? _readable(Uint8List bytes) {
  try {
    return SyncEvent.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// The chat ID, keys, privacy and password in toxcore's save of a group, as
/// `tox_group_get_savedata` wrote it, or null if it isn't one.
({
  GroupChatId chatId,
  GroupSecretKey self,
  GroupSecretKey? chat,
  Privacy privacy,
  String password,
})?
_keptGroup(Uint8List state) {
  void skip(Unpacker u, int count) {
    for (var i = 0; i < count; ++i) {
      u.skip();
    }
  }

  // A key is the encryption key, then the signing key. A secret signing key
  // is its seed, then its public key, which is the chat ID for the group's.
  const seedStart = 32;
  const signingStart = 32;
  GroupSecretKey seedOf(Uint8List key) => GroupSecretKey(
    key.sublist(seedStart, seedStart + GroupSecretKey.kLength),
  );

  try {
    final u = Unpacker(state)..unpackListLength();

    // The shared state's values: whether we left, the name's length, the
    // privacy state, and five more.
    u.unpackListLength();
    skip(u, 2);
    final privacy = GroupPrivacyState.fromValue(u.unpackInt()!);
    skip(u, 5);

    // Its bytes: signature, founder, name, password and the moderators' hash.
    u.unpackListLength();
    skip(u, 3);
    final password = utf8.decode(u.unpackBinary()!, allowMalformed: true);
    skip(u, 1);

    // The topic and the moderators.
    skip(u, 2);

    // The group's public and secret key, then ours.
    u.unpackListLength();
    final chatPublic = u.unpackBinary()!;
    final chat = u.unpackBinary()!;
    skip(u, 1);
    final self = u.unpackBinary()!;

    return (
      chatId: GroupChatId(
        chatPublic.sublist(signingStart, signingStart + toxGroupChatIdSize),
      ),
      self: seedOf(self),
      // Only the founder has the group's secret key.
      chat: chat.every((b) => b == 0) ? null : seedOf(chat),
      privacy: privacy == GroupPrivacyState.private
          ? Privacy.private
          : Privacy.public,
      password: password,
    );
  } on Object catch (_) {
    return null;
  }
}
