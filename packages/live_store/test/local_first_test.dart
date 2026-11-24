import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('Local-First primitives', () {
    test('generateUuidV7 generates valid RFC 9562 UUIDv7', () {
      final id1 = generateUuidV7();
      final id2 = generateUuidV7();

      expect(id1, isNot(id2));
      // Format: 8-4-4-4-12 hex characters
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id1),
        isTrue,
        reason: 'UUIDv7 must match RFC 9562 format with version 7 and variant 1',
      );
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id2),
        isTrue,
      );
    });

    test('hybridLogicalClock produces monotonic timestamps', () {
      final t1 = hybridLogicalClock();
      final t2 = hybridLogicalClock(t1);
      final t3 = hybridLogicalClock(t2);

      expect(t2, greaterThan(t1));
      expect(t3, greaterThan(t2));
    });
  });

  group('Local-First database contracts', () {
    test('follows store populates sync_id, updated_at, and is_deleted', () async {
      final store = await memoryStore();
      final room = LiveRoom(platform: 'huya', roomId: '10188', nick: 'DANK1NG');

      await store.follows.add(room);

      final rows = await store.database.rows('SELECT sync_id, updated_at, is_deleted FROM follows WHERE identity = ?', [
        room.identityKey,
      ]);
      expect(rows, hasLength(1));
      final syncId = rows.single.read<String>('sync_id');
      final updatedAt = rows.single.read<int>('updated_at');
      final isDeleted = rows.single.read<int>('is_deleted');

      expect(syncId, isNotEmpty);
      expect(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7').hasMatch(syncId), isTrue);
      expect(updatedAt, greaterThan(0));
      expect(isDeleted, equals(0));
    });

    test('history store populates sync_id, updated_at, and is_deleted', () async {
      final store = await memoryStore();
      final room = LiveRoom(platform: 'douyu', roomId: '6657', nick: 'Machine');

      await store.history.record(room);

      final rows = await store.database.rows('SELECT sync_id, updated_at, is_deleted FROM history WHERE identity = ?', [
        room.identityKey,
      ]);
      expect(rows, hasLength(1));
      final syncId = rows.single.read<String>('sync_id');
      final updatedAt = rows.single.read<int>('updated_at');
      final isDeleted = rows.single.read<int>('is_deleted');

      expect(syncId, isNotEmpty);
      expect(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7').hasMatch(syncId), isTrue);
      expect(updatedAt, greaterThan(0));
      expect(isDeleted, equals(0));
    });

    test('follow areas store populates sync_id, updated_at, and is_deleted', () async {
      final store = await memoryStore();
      const area = LiveArea(platform: 'huya', areaId: '1', areaName: '网游');

      await store.followAreas.add(area);

      final rows = await store.database.rows('SELECT sync_id, updated_at, is_deleted FROM follow_areas WHERE identity = ?', [
        area.identityKey,
      ]);
      expect(rows, hasLength(1));
      final syncId = rows.single.read<String>('sync_id');
      final updatedAt = rows.single.read<int>('updated_at');
      final isDeleted = rows.single.read<int>('is_deleted');

      expect(syncId, isNotEmpty);
      expect(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7').hasMatch(syncId), isTrue);
      expect(updatedAt, greaterThan(0));
      expect(isDeleted, equals(0));
    });
  });

  group('LocalFirstSyncManager & NSFW Isolation Gate', () {
    test('exportDelta strictly excludes NSFW rooms and areas (100% physical filter)', () async {
      final store = await memoryStore();

      // Add normal rooms
      final normalRoom = LiveRoom(platform: 'bilibili', roomId: '12345', nick: 'Normal Streamer');
      await store.follows.add(normalRoom);

      // Add NSFW room (stripchat is marked isNsfw: true in sites.dart)
      final nsfwRoom = LiveRoom(platform: 'stripchat', roomId: '99999', nick: 'Private Cam');
      await store.follows.add(nsfwRoom);

      // Add normal history and NSFW history
      await store.history.record(normalRoom);
      await store.history.record(nsfwRoom);

      // Add normal area and NSFW area
      const normalArea = LiveArea(platform: 'huya', areaId: '10', areaName: '网游');
      const nsfwArea = LiveArea(platform: 'chaturbate', areaId: 'female', areaName: 'Female');
      await store.followAreas.add(normalArea);
      await store.followAreas.add(nsfwArea);

      // Verify that database indeed contains both records internally
      expect(await store.follows.all(), hasLength(2));
      expect(await store.history.all(), hasLength(2));
      expect(await store.followAreas.all(), hasLength(2));

      // Now run exportDelta
      final delta = await store.syncManager.exportDelta();

      final follows = (delta['follows']! as List).cast<Map<String, Object?>>();
      final history = (delta['history']! as List).cast<Map<String, Object?>>();
      final areas = (delta['followAreas']! as List).cast<Map<String, Object?>>();

      // NSFW records MUST be completely absent from delta
      expect(follows, hasLength(1));
      expect((follows.first['room']! as Map)['platform'], 'bilibili');
      expect(follows.any((f) => (f['room']! as Map)['platform'] == 'stripchat'), isFalse);

      expect(history, hasLength(1));
      expect((history.first['room']! as Map)['platform'], 'bilibili');
      expect(history.any((h) => (h['room']! as Map)['platform'] == 'stripchat'), isFalse);

      expect(areas, hasLength(1));
      expect((areas.first['area']! as Map)['platform'], 'huya');
      expect(areas.any((a) => (a['area']! as Map)['platform'] == 'chaturbate'), isFalse);
    });

    test('applyDelta applies remote changes and enforces LWW', () async {
      final storeA = await memoryStore();
      final storeB = await memoryStore();

      final room1 = LiveRoom(platform: 'douyu', roomId: '11111', nick: 'Douyu Streamer');
      await storeA.follows.add(room1);

      final deltaA = await storeA.syncManager.exportDelta();
      final applied = await storeB.syncManager.applyDelta(deltaA);
      expect(applied, 1);

      final followsB = await storeB.follows.all();
      expect(followsB, hasLength(1));
      expect(followsB.first.roomId, '11111');

      // Applying older or same delta to storeA should not overwrite (LWW)
      final reapplied = await storeA.syncManager.applyDelta(deltaA);
      expect(reapplied, 0);
    });

    test('exportEncryptedDelta and applyEncryptedDelta roundtrip', () async {
      final storeSender = await memoryStore();
      final storeReceiver = await memoryStore();

      await storeSender.follows.add(LiveRoom(platform: 'huya', roomId: '520', nick: 'Huya Star'));

      const syncPassphrase = 'SyncPassword!999';
      final encryptedBytes = await storeSender.syncManager.exportEncryptedDelta(syncPassphrase);

      expect(encryptedBytes, isNotEmpty);

      // Decrypt and apply on receiver
      final modifiedCount = await storeReceiver.syncManager.applyEncryptedDelta(
        encryptedBytes,
        syncPassphrase,
      );

      expect(modifiedCount, 1);
      final receivedFollows = await storeReceiver.follows.all();
      expect(receivedFollows, hasLength(1));
      expect(receivedFollows.first.roomId, '520');
    });

    test('BackupService exportAll and exportFollows 100% exclude NSFW', () async {
      final store = await memoryStore();
      final backup = BackupService(store);

      await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '1', nick: 'Bili'));
      await store.follows.add(LiveRoom(platform: 'stripchat', roomId: '2', nick: 'Strip'));

      await store.history.record(LiveRoom(platform: 'douyu', roomId: '3', nick: 'Douyu'));
      await store.history.record(LiveRoom(platform: 'chaturbate', roomId: '4', nick: 'Chaturbate'));

      final allBackup = await backup.exportAll();
      final favSection = allBackup['favorite']! as Map<String, Object?>;
      final histSection = allBackup['history']! as Map<String, Object?>;

      final favRooms = favSection['favoriteRooms']! as List;
      final histRooms = histSection['historyRooms']! as List;

      expect(favRooms, hasLength(1));
      expect((favRooms.first as Map)['platform'], 'bilibili');

      expect(histRooms, hasLength(1));
      expect((histRooms.first as Map)['platform'], 'douyu');

      final favBackup = await backup.exportFollows();
      final favOnlyRooms = (favBackup['favorite']! as Map)['favoriteRooms']! as List;
      expect(favOnlyRooms, hasLength(1));
      expect((favOnlyRooms.first as Map)['platform'], 'bilibili');
    });
  });
}
