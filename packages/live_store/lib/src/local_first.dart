import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/crypto/sync_cipher.dart';
import 'package:live_store/src/database.dart';
import 'package:live_store/src/live_store.dart';

/// RFC 9562 UUIDv7 generator for Local-First entity identities.
///
/// Uses 48-bit UNIX epoch timestamp in milliseconds for time-based ordering,
/// followed by 74 bits of cryptographically secure random entropy.
String generateUuidV7() {
  final random = math.Random.secure();
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  final timeHigh = (nowMs >> 16) & 0xFFFFFFFF;
  final timeLow = nowMs & 0xFFFF;
  final verRandom = 0x7000 | random.nextInt(0x1000);
  final varRandom = 0x8000 | random.nextInt(0x4000);
  final rand1 = random.nextInt(0x10000);
  final rand2 = random.nextInt(0x10000);
  final rand3 = random.nextInt(0x10000);

  String hex(int val, int width) => val.toRadixString(16).padLeft(width, '0');

  return '${hex(timeHigh, 8)}-${hex(timeLow, 4)}-${hex(verRandom, 4)}-${hex(varRandom, 4)}-${hex(rand1, 4)}${hex(rand2, 4)}${hex(rand3, 4)}';
}

/// Hybrid Logical Clock (HLC) timestamp in microseconds.
///
/// Generates a monotonically non-decreasing timestamp in UTC.
int hybridLogicalClock([int lastHlc = 0]) {
  final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
  return nowUs > lastHlc ? nowUs : lastHlc + 1;
}

/// Local-First incremental change-log synchronization manager for PureLive 4.x.
///
/// Implements:
/// - Delta export/import based on Hybrid Logical Clock watermarks (`updated_at > sinceHlc`).
/// - Last-Write-Wins (LWW) conflict resolution for concurrent edits across devices.
/// - Soft-deletes propagation via `is_deleted` column.
/// - Hard Invariant: 100% physical exclusion of NSFW data on export and import.
/// - End-to-end AES-256-GCM encryption with PBKDF2 key derivation.
final class LocalFirstSyncManager {
  /// Creates the manager for [_store].
  const new(this._store);

  final LiveStore _store;

  StoreDatabase get _db => _store.database;

  /// Exports incremental delta changes created or updated after [sinceHlc].
  ///
  /// Strictly filters out any room or area where `SiteIds.descriptorOf(platform).isNsfw == true`.
  Future<Map<String, Object?>> exportDelta({int sinceHlc = 0, String? deviceId}) async {
    final followRows = await _db.rows(
      'SELECT identity, position, room, sync_id, updated_at, is_deleted FROM follows WHERE updated_at > ?',
      [sinceHlc],
    );
    final follows = <Map<String, Object?>>[];
    for (final row in followRows) {
      final roomJsonStr = row.read<String>('room');
      final roomMap = jsonDecode(roomJsonStr) as Map<String, Object?>;
      final platform = (roomMap['platform'] as String? ?? '').trim().toLowerCase();
      if (SiteIds.descriptorOf(platform).isNsfw) continue;

      follows.add({
        'identity': row.read<String>('identity'),
        'position': row.read<int>('position'),
        'room': roomMap,
        'syncId': row.read<String>('sync_id'),
        'updatedAt': row.read<int>('updated_at'),
        'isDeleted': row.read<int>('is_deleted') == 1,
      });
    }

    final historyRows = await _db.rows(
      'SELECT identity, seq, room, sync_id, updated_at, is_deleted FROM history WHERE updated_at > ?',
      [sinceHlc],
    );
    final history = <Map<String, Object?>>[];
    for (final row in historyRows) {
      final roomJsonStr = row.read<String>('room');
      final roomMap = jsonDecode(roomJsonStr) as Map<String, Object?>;
      final platform = (roomMap['platform'] as String? ?? '').trim().toLowerCase();
      if (SiteIds.descriptorOf(platform).isNsfw) continue;

      history.add({
        'identity': row.read<String>('identity'),
        'seq': row.read<int>('seq'),
        'room': roomMap,
        'syncId': row.read<String>('sync_id'),
        'updatedAt': row.read<int>('updated_at'),
        'isDeleted': row.read<int>('is_deleted') == 1,
      });
    }

    final areaRows = await _db.rows(
      'SELECT identity, position, area, sync_id, updated_at, is_deleted FROM follow_areas WHERE updated_at > ?',
      [sinceHlc],
    );
    final followAreas = <Map<String, Object?>>[];
    for (final row in areaRows) {
      final areaJsonStr = row.read<String>('area');
      final areaMap = jsonDecode(areaJsonStr) as Map<String, Object?>;
      final platform = (areaMap['platform'] as String? ?? '').trim().toLowerCase();
      if (SiteIds.descriptorOf(platform).isNsfw) continue;

      followAreas.add({
        'identity': row.read<String>('identity'),
        'position': row.read<int>('position'),
        'area': areaMap,
        'syncId': row.read<String>('sync_id'),
        'updatedAt': row.read<int>('updated_at'),
        'isDeleted': row.read<int>('is_deleted') == 1,
      });
    }

    final tagRows = await _db.rows(
      'SELECT id, position, name, description, updated_at, is_deleted FROM tags WHERE updated_at > ?',
      [sinceHlc],
    );
    final tags = [
      for (final row in tagRows)
        {
          'id': row.read<String>('id'),
          'position': row.read<int>('position'),
          'name': row.read<String>('name'),
          'description': row.read<String>('description'),
          'updatedAt': row.read<int>('updated_at'),
          'isDeleted': row.read<int>('is_deleted') == 1,
        },
    ];

    final roomTagRows = await _db.rows(
      'SELECT room, tag_id, position, updated_at, is_deleted FROM room_tags WHERE updated_at > ?',
      [sinceHlc],
    );
    final roomTags = [
      for (final row in roomTagRows)
        {
          'room': row.read<String>('room'),
          'tagId': row.read<String>('tag_id'),
          'position': row.read<int>('position'),
          'updatedAt': row.read<int>('updated_at'),
          'isDeleted': row.read<int>('is_deleted') == 1,
        },
    ];

    final blockRuleRows = await _db.rows(
      'SELECT kind, folded, value, position, updated_at, is_deleted FROM block_rules WHERE updated_at > ?',
      [sinceHlc],
    );
    final blockRules = [
      for (final row in blockRuleRows)
        {
          'kind': row.read<String>('kind'),
          'folded': row.read<String>('folded'),
          'value': row.read<String>('value'),
          'position': row.read<int>('position'),
          'updatedAt': row.read<int>('updated_at'),
          'isDeleted': row.read<int>('is_deleted') == 1,
        },
    ];

    return {
      'syncVersion': 4,
      'deviceId': deviceId ?? '',
      'sinceHlc': sinceHlc,
      'watermarkHlc': hybridLogicalClock(),
      'follows': follows,
      'history': history,
      'followAreas': followAreas,
      'tags': tags,
      'roomTags': roomTags,
      'blockRules': blockRules,
    };
  }

  /// Applies incoming [delta] changes with Last-Write-Wins (LWW) conflict resolution.
  ///
  /// Returns the number of applied record modifications.
  Future<int> applyDelta(Map<String, Object?> delta) async {
    var modified = 0;
    final affectedTables = <String>{};

    if (delta['follows'] case final List<dynamic> items) {
      for (final item in items.whereType<Map<String, Object?>>()) {
        final identity = item['identity'] as String?;
        final roomMap = item['room'] as Map<String, Object?>?;
        final updatedAt = item['updatedAt'] as int? ?? 0;
        final isDeleted = item['isDeleted'] == true ? 1 : 0;
        final position = item['position'] as int? ?? 0;
        final syncId = (item['syncId'] as String?)?.isNotEmpty == true
            ? item['syncId']! as String
            : generateUuidV7();

        if (identity == null || roomMap == null) continue;
        final platform = (roomMap['platform'] as String? ?? '').trim().toLowerCase();
        if (SiteIds.descriptorOf(platform).isNsfw) continue;

        final existing = await _db.rows('SELECT updated_at FROM follows WHERE identity = ?', [identity]);
        if (existing.isNotEmpty && existing.single.read<int>('updated_at') >= updatedAt) {
          continue; // Local record is newer or same
        }

        await _db.run(
          'INSERT OR REPLACE INTO follows (identity, position, room, sync_id, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?)',
          [identity, position, jsonEncode(roomMap), syncId, updatedAt, isDeleted],
        );
        modified++;
        affectedTables.add(StoreTables.follows);
      }
    }

    if (delta['history'] case final List<dynamic> items) {
      for (final item in items.whereType<Map<String, Object?>>()) {
        final identity = item['identity'] as String?;
        final roomMap = item['room'] as Map<String, Object?>?;
        final updatedAt = item['updatedAt'] as int? ?? 0;
        final isDeleted = item['isDeleted'] == true ? 1 : 0;
        final seq = item['seq'] as int? ?? 0;
        final syncId = (item['syncId'] as String?)?.isNotEmpty == true
            ? item['syncId']! as String
            : generateUuidV7();

        if (identity == null || roomMap == null) continue;
        final platform = (roomMap['platform'] as String? ?? '').trim().toLowerCase();
        if (SiteIds.descriptorOf(platform).isNsfw) continue;

        final existing = await _db.rows('SELECT updated_at FROM history WHERE identity = ?', [identity]);
        if (existing.isNotEmpty && existing.single.read<int>('updated_at') >= updatedAt) {
          continue;
        }

        await _db.run(
          'INSERT OR REPLACE INTO history (identity, seq, room, sync_id, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?)',
          [identity, seq, jsonEncode(roomMap), syncId, updatedAt, isDeleted],
        );
        modified++;
        affectedTables.add(StoreTables.history);
      }
    }

    if (delta['followAreas'] case final List<dynamic> items) {
      for (final item in items.whereType<Map<String, Object?>>()) {
        final identity = item['identity'] as String?;
        final areaMap = item['area'] as Map<String, Object?>?;
        final updatedAt = item['updatedAt'] as int? ?? 0;
        final isDeleted = item['isDeleted'] == true ? 1 : 0;
        final position = item['position'] as int? ?? 0;
        final syncId = (item['syncId'] as String?)?.isNotEmpty == true
            ? item['syncId']! as String
            : generateUuidV7();

        if (identity == null || areaMap == null) continue;
        final platform = (areaMap['platform'] as String? ?? '').trim().toLowerCase();
        if (SiteIds.descriptorOf(platform).isNsfw) continue;

        final existing = await _db.rows('SELECT updated_at FROM follow_areas WHERE identity = ?', [identity]);
        if (existing.isNotEmpty && existing.single.read<int>('updated_at') >= updatedAt) {
          continue;
        }

        await _db.run(
          'INSERT OR REPLACE INTO follow_areas (identity, position, area, sync_id, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?)',
          [identity, position, jsonEncode(areaMap), syncId, updatedAt, isDeleted],
        );
        modified++;
        affectedTables.add(StoreTables.followAreas);
      }
    }

    if (affectedTables.isNotEmpty) {
      await _db.notifyAllTables();
    }

    return modified;
  }

  /// Exports and encrypts delta changes using [passphrase] with AES-256-GCM.
  Future<Uint8List> exportEncryptedDelta(
    String passphrase, {
    int sinceHlc = 0,
    String? deviceId,
  }) async {
    final delta = await exportDelta(sinceHlc: sinceHlc, deviceId: deviceId);
    return SyncCipher.packEncryptedPayload(delta, passphrase);
  }

  /// Decrypts and applies delta changes from [packetBytes] using [passphrase].
  Future<int> applyEncryptedDelta(List<int> packetBytes, String passphrase) async {
    final delta = SyncCipher.unpackEncryptedPayload(packetBytes, passphrase);
    return await applyDelta(delta);
  }
}
