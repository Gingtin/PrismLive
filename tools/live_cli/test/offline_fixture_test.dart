import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('Offline Fixture Store Tests', () {
    const store = OfflineFixtureStore();

    test('loads Bilibili offline fixture accurately', () {
      final room = store.getRoom('bilibili');
      expect(room, isNotNull);
      expect(room!.platform, equals('bilibili'));
      expect(room.roomId, equals('6'));
      expect(room.liveStatus, equals(LiveStatus.live));

      final qualities = store.getQualities('bilibili');
      expect(qualities.length, equals(2));
      expect(qualities.first.quality, equals('原画'));
      expect((qualities.first.data! as List).first, contains('bilivideo.com'));
    });

    test('loads Douyu offline fixture accurately', () {
      final room = store.getRoom('douyu');
      expect(room, isNotNull);
      expect(room!.platform, equals('douyu'));
      expect(room.liveStatus, equals(LiveStatus.live));

      final qualities = store.getQualities('douyu');
      expect(qualities.isNotEmpty, isTrue);
      expect((qualities.first.data! as List).first, contains('douyucdn.cn'));
    });

    test('loads Twitch and YouTube offline fixtures', () {
      final twitchRoom = store.getRoom('twitch');
      expect(twitchRoom, isNotNull);
      expect(twitchRoom!.platform, equals('twitch'));

      final ytbRoom = store.getRoom('youtube');
      expect(ytbRoom, isNotNull);
      expect(ytbRoom!.platform, equals('youtube'));
    });

    test('returns null for missing platform fixture', () {
      final missing = store.getRoom('non_existent_platform');
      expect(missing, isNull);
    });
  });
}
