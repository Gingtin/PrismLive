import 'package:live_core/live_core.dart';
import 'package:live_store/src/local_first.dart';
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
}
