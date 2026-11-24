import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

void main() {
  group('DanmakuSimHashFilter', () {
    late DanmakuSimHashFilter filter;

    setUp(() {
      filter = DanmakuSimHashFilter(maxCapacity: 128);
    });

    tearDown(() {
      filter.dispose();
    });

    test('accepts unique messages', () {
      expect(filter.shouldDisplay('主播技术真好'), isTrue);
      expect(filter.shouldDisplay('明天几点开播呢'), isTrue);
      expect(filter.shouldDisplay('关注了主播'), isTrue);
      expect(filter.shouldDisplay('666'), isTrue);
    });

    test('rejects empty or whitespace-only messages', () {
      expect(filter.shouldDisplay(''), isFalse);
      expect(filter.shouldDisplay('   \t\n'), isFalse);
    });

    test('filters near-duplicate spam with slight variations', () {
      // First one is displayed
      expect(filter.shouldDisplay('主播太强了666666'), isTrue);
      // Repeated suffix spam should be detected and filtered
      expect(filter.shouldDisplay('主播太强了66666'), isFalse);
      expect(filter.shouldDisplay('主播太强了666666'), isFalse);
    });

    test('clear resets the filter history', () {
      expect(filter.shouldDisplay('第一条测试弹幕'), isTrue);
      expect(filter.shouldDisplay('第一条测试弹幕'), isFalse);

      filter.clear();

      // After clear, same message should be accepted again
      expect(filter.shouldDisplay('第一条测试弹幕'), isTrue);
    });

    test('evicts oldest entries when capacity is exceeded', () {
      final smallFilter = DanmakuSimHashFilter(maxCapacity: 3, maxDistance: 1);
      try {
        expect(smallFilter.shouldDisplay('item_alpha_unique_1'), isTrue);
        expect(smallFilter.shouldDisplay('item_beta_unique_2'), isTrue);
        expect(smallFilter.shouldDisplay('item_gamma_unique_3'), isTrue);

        // Fourth distinct item evicts alpha_1
        expect(smallFilter.shouldDisplay('item_delta_unique_4'), isTrue);

        // alpha_1 was evicted, so it should be allowed again
        expect(smallFilter.shouldDisplay('item_alpha_unique_1'), isTrue);
      } finally {
        smallFilter.dispose();
      }
    });

    test('DanmakuSimilarityFilter with useSimHash = true delegates correctly', () {
      final simFilter = DanmakuSimilarityFilter(useSimHash: true);
      try {
        expect(simFilter.useSimHash, isTrue);
        expect(simFilter.shouldDisplay('主播太强了666666'), isTrue);
        expect(simFilter.shouldDisplay('主播太强了66666'), isFalse);
        expect(simFilter.shouldDisplay('换个话题完全不同'), isTrue);
      } finally {
        simFilter.dispose();
      }
    });

    test('sub-millisecond throughput benchmark', () {
      final benchFilter = DanmakuSimHashFilter();
      final stopwatch = Stopwatch()..start();
      const count = 1000;
      for (var i = 0; i < count; i++) {
        benchFilter.shouldDisplay('这是一条压力测试弹幕编号$i，检查判重效率');
      }
      stopwatch.stop();
      // 1000 items should complete in < 200ms
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
      benchFilter.dispose();
    });
  });
}
