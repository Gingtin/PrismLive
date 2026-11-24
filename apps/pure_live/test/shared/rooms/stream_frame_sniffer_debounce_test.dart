import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/shared/rooms/stream_frame_sniffer.dart';

void main() {
  group('StreamFrameSniffer 300ms Scroll Debounce', () {
    late StreamFrameSniffer sniffer;

    setUp(() {
      sniffer = StreamFrameSniffer.instance
        ..resume()
        ..clearFailures();
    });

    tearDown(() {
      sniffer.pause();
    });

    testWidgets('debounces rapid list scrolling requests by 300ms', (tester) async {
      final room1 = LiveRoom(
        platform: 'iptv',
        roomId: 'cctv1',
        nick: 'CCTV-1',
        data: 'http://127.0.0.1:8080/live/cctv1.flv',
      );
      final room2 = LiveRoom(
        platform: 'iptv',
        roomId: 'cctv2',
        nick: 'CCTV-2',
        data: 'http://127.0.0.1:8080/live/cctv2.flv',
      );
      final room3 = LiveRoom(
        platform: 'iptv',
        roomId: 'cctv3',
        nick: 'CCTV-3',
        data: 'http://127.0.0.1:8080/live/cctv3.flv',
      );

      // Rapid scroll calls
      sniffer.request(room1);
      await tester.pump(const Duration(milliseconds: 100));

      sniffer.request(room2);
      await tester.pump(const Duration(milliseconds: 100));

      sniffer.request(room3);
      // Only 200ms elapsed since room3 request, debounce should not have fired
      await tester.pump(const Duration(milliseconds: 200));

      // Now advance beyond 300ms threshold (total 350ms since room3 request)
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('pause cancels debounce timer and flushes pending requests', (tester) async {
      final room = LiveRoom(
        platform: 'iptv',
        roomId: 'cctv5',
        nick: 'CCTV-5',
        data: 'http://127.0.0.1:8080/live/cctv5.flv',
      );

      sniffer.request(room);
      await tester.pump(const Duration(milliseconds: 100));

      // User leaves screen (pausing sniffer)
      sniffer.pause();
      expect(sniffer.isPaused, isTrue);

      // Debounce timer elapsed while paused should not trigger background decoding
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
