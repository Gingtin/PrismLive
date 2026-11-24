import 'dart:io';

import 'package:live_bridge/live_bridge.dart';
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('PureLiveCoreBridge Rust Native Tests', () {
    test('native bridge loads and reports valid engine version', () {
      final bridge = PureLiveCoreBridge.instance;
      expect(bridge, isNotNull, reason: 'purelive_core_rs native binary should be built');
      expect(bridge!.version, equals('0.1.0'));
    });

    test('relay engine starts on ephemeral loopback port and handles sessions', () {
      final bridge = PureLiveCoreBridge.instance!;
      final relay = bridge.createRelay();
      expect(relay, isNotNull);
      expect(relay!.port, greaterThan(0));

      final loopbackUrl = relay.registerSession(
        sessionId: 'test_session_1',
        upstreamUrl: 'https://example.com/live/stream.flv',
        site: 'bilibili',
        networkMode: NetworkMode.direct,
      );

      expect(loopbackUrl, isNotNull);
      expect(loopbackUrl, contains('http://127.0.0.1:${relay.port}/stream/test_session_1'));

      // Stream Tee recording state
      expect(relay.isRecording('test_session_1'), isFalse);

      final tempDir = Directory.systemTemp.createTempSync('live_bridge_record_');
      try {
        final startSuccess = relay.startRecord(
          sessionId: 'test_session_1',
          outputDir: tempDir.path,
          filePrefix: 'test_rec',
          maxDurationSecs: 3600,
          maxBytes: 1024 * 1024 * 100,
        );
        expect(startSuccess, isTrue);

        // Stopping record
        final stopSuccess = relay.stopRecord('test_session_1');
        expect(stopSuccess, isTrue);
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
        } on Object catch (_) {}
      }

      relay.unregisterSession('test_session_1');
      relay.dispose();
      expect(relay.isClosed, isTrue);
    });
  });
}
