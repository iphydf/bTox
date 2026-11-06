import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/fact.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:toxcore/messagepack.dart';
import 'package:toxcore/tox.dart' show GroupPrivacyState;

import '../drift/btox/generated/schema.dart';
import '../drift/btox/generated/schema_v2.dart' as v2;
import '../drift/btox/generated/schema_v3.dart' as v3;

final _chatId = GroupChatId(Uint8List.fromList(List.filled(32, 1)));
final _chatKey = GroupSecretKey(Uint8List.fromList(List.filled(32, 2)));
final _selfKey = GroupSecretKey(Uint8List.fromList(List.filled(32, 3)));
final _memberKey = GroupSecretKey(Uint8List.fromList(List.filled(32, 4)));

/// Toxcore's save of a group, as `gc_save_pack_group` in c-toxcore's
/// group_pack.c packs it. Keys are made up: only their layout matters.
Uint8List _toxcoreSave({
  required GroupChatId chatId,
  required GroupSecretKey self,
  GroupSecretKey? chat,
  required GroupPrivacyState privacy,
  required String password,
}) {
  final encryption = Uint8List(32);
  final publicKey = Uint8List(32);
  // A public key is the encryption key, then the signing key. A secret key is
  // the encryption key, then the signing key: its seed and its public key.
  Uint8List secret(GroupSecretKey seed, Uint8List signing) =>
      Uint8List.fromList([...encryption, ...seed.bytes, ...signing]);
  final name = utf8.encode('Lab');
  final p = Packer()..packListLength(7);
  // The shared state's values: whether we left, the name's length, the privacy
  // state, the peer limit, the password's length, the version, the topic lock
  // and the voice state.
  p
    ..packListLength(8)
    ..packBool(false)
    ..packInt(name.length)
    ..packInt(privacy.value)
    ..packInt(100)
    ..packInt(password.length)
    ..packInt(2)
    ..packInt(0)
    ..packInt(0);
  // Its bytes: signature, founder, name, password and the moderators' hash.
  p
    ..packListLength(5)
    ..packBinary(Uint8List(64))
    ..packBinary(Uint8List(64))
    ..packBinary(name)
    ..packBinary(utf8.encode(password))
    ..packBinary(Uint8List(32));
  // The topic: version, length, checksum, text, its setter and signature.
  p
    ..packListLength(6)
    ..packInt(1)
    ..packInt(0)
    ..packInt(0)
    ..packBinary(Uint8List(0))
    ..packBinary(Uint8List(32))
    ..packBinary(Uint8List(64));
  // No moderators.
  p
    ..packListLength(2)
    ..packInt(0)
    ..packNull();
  // The group's public and secret key, then ours. Only the founder has the
  // group's secret key: a member's is zeros.
  p
    ..packListLength(4)
    ..packBinary([...encryption, ...chatId.bytes])
    ..packBinary(chat == null ? Uint8List(96) : secret(chat, chatId.bytes))
    ..packBinary([...encryption, ...publicKey])
    ..packBinary(secret(self, publicKey));
  // Our nick's length, role, status and nick.
  p
    ..packListLength(4)
    ..packInt(2)
    ..packInt(0)
    ..packInt(0)
    ..packBinary(utf8.encode('Me'));
  // No saved peers.
  p
    ..packListLength(2)
    ..packInt(0)
    ..packNull();
  return p.takeBytes();
}

void main() {
  late File file;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('btox_migration_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}/bTox.sqlite');
  });

  test('a schema version without a migration step keeps the data', () async {
    final db = Database(NativeDatabase(file));
    await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    final version = db.schemaVersion;
    await db.close();

    // E.g. an older app installed over a newer one's database.
    void setVersion(int version) => sqlite3.open(file.path)
      ..execute('PRAGMA user_version = $version;')
      ..dispose();
    setVersion(version + 1);

    final mismatched = Database(NativeDatabase(file));
    await expectLater(mismatched.watchProfiles().first, throwsA(anything));
    await mismatched.close();

    setVersion(version);
    final reopened = Database(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(await reopened.watchProfiles().first, hasLength(1));
  });

  test('a group toxcore saved comes back as its keys', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    final profile = await old
        .into(old.profiles)
        .insert(
          v2.ProfilesCompanion.insert(
            settings: const ProfileSettingsConverter().toSql(
              ProfileSettings(nickname: 'Me', statusMessage: ''),
            ),
            secretKey: SecretKey(Uint8List(32)).toJson(),
            publicKey: PublicKey(Uint8List(32)).toJson(),
            nospam: 0,
          ),
        );
    final memberChatId = GroupChatId(Uint8List.fromList(List.filled(32, 5)));
    for (final (chatId, state) in [
      (
        _chatId,
        _toxcoreSave(
          chatId: _chatId,
          self: _selfKey,
          chat: _chatKey,
          privacy: GroupPrivacyState.private,
          password: 'pw',
        ),
      ),
      (
        memberChatId,
        _toxcoreSave(
          chatId: memberChatId,
          self: _memberKey,
          privacy: GroupPrivacyState.public,
          password: '',
        ),
      ),
    ]) {
      await old
          .into(old.chatSaves)
          .insert(
            v2.ChatSavesCompanion.insert(
              profileId: profile,
              graph: GraphId.group(chatId).toJson(),
              kind: 'group',
              state: state,
            ),
          );
    }
    await old.close();

    final db = Database(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
    final kept = {
      for (final membership in await db.getGroupMemberships(Id(profile)))
        membership.chatId: membership,
    };
    final founder = kept[_chatId]!;
    final member = kept[memberChatId]!;
    expect(founder.selfSecretKey, _selfKey);
    expect(founder.chatSecretKey, _chatKey);
    expect(founder.privacy, Privacy.private);
    expect(founder.password, 'pw');
    expect(founder.state, isNull);
    expect(member.selfSecretKey, _memberKey);
    expect(member.chatSecretKey, isNull);
    expect(member.privacy, Privacy.public);
  });

  test('a group kept with endpoints keeps its keys', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    final profile = await old
        .into(old.profiles)
        .insert(
          v3.ProfilesCompanion.insert(
            settings: const ProfileSettingsConverter().toSql(
              ProfileSettings(nickname: 'Me', statusMessage: ''),
            ),
            secretKey: SecretKey(Uint8List(32)).toJson(),
            publicKey: PublicKey(Uint8List(32)).toJson(),
            nospam: 0,
          ),
        );
    await old
        .into(old.groupMemberships)
        .insert(
          v3.GroupMembershipsCompanion.insert(
            profileId: profile,
            chatId: _chatId.toJson(),
            selfSecretKey: _selfKey.toJson(),
            chatSecretKey: Value(_chatKey.toJson()),
            privacy: 'private',
            password: 'pw',
            endpoints: '[{"publicKey":"${'02' * 32}","ip":"10.1.2.3",'
                '"port":33445,"relayPublicKey":null,"relayIp":null,'
                '"relayPort":0}]',
          ),
        );
    await old.close();

    final db = Database(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
    final [kept] = await db.getGroupMemberships(Id(profile));
    expect(kept.chatId, _chatId);
    expect(kept.selfSecretKey, _selfKey);
    expect(kept.chatSecretKey, _chatKey);
    expect(kept.privacy, Privacy.private);
    expect(kept.password, 'pw');
    expect(kept.state, isNull);
  });
}
