import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/decoder_budget_manager.dart';

void main() {
  group('DecoderBudgetManager', () {
    test('allocates hardware decoder up to max budget', () {
      final notices = <String>[];
      final manager = DecoderBudgetManager(
        maxHardwareDecoders: 2,
        onBudgetNotice: notices.add,
      );

      // Cell 1: hardware
      expect(manager.allocateDecoderForCell(1), DecoderMode.hardware);
      // Cell 2: hardware
      expect(manager.allocateDecoderForCell(2), DecoderMode.hardware);

      // Cell 3: exceeds budget -> software fallback + notice
      expect(manager.allocateDecoderForCell(3), DecoderMode.software);
      expect(notices, hasLength(1));
      expect(notices.first, contains('软解'));
    });

    test('prioritizes focused or audible cell with hardware decoding', () {
      final manager = DecoderBudgetManager(maxHardwareDecoders: 1);

      // Cell 1 takes the 1 slot
      expect(manager.allocateDecoderForCell(1), DecoderMode.hardware);

      // Cell 2 is audible -> gets hardware even if budget was full
      expect(
        manager.allocateDecoderForCell(2, isAudible: true),
        DecoderMode.hardware,
      );

      // Cell 3 is focused -> gets hardware
      manager.focusedCellId = 3;
      expect(manager.allocateDecoderForCell(3), DecoderMode.hardware);
    });

    test('releasing cell frees hardware decoder slot', () {
      final manager = DecoderBudgetManager(maxHardwareDecoders: 1);

      expect(manager.allocateDecoderForCell(1), DecoderMode.hardware);
      expect(manager.allocateDecoderForCell(2), DecoderMode.software);

      manager.releaseCell(1);
      // Slot 1 freed, cell 2 can now get hardware
      expect(manager.allocateDecoderForCell(2), DecoderMode.hardware);
    });

    test('reset clears allocations and focus', () {
      final manager = DecoderBudgetManager(maxHardwareDecoders: 2)
        ..focusedCellId = 10
        ..allocateDecoderForCell(1)
        ..allocateDecoderForCell(2)
        ..reset();

      expect(manager.focusedCellId, isNull);
    });
  });

  group('PlaybackTerminalState', () {
    test('StreamOfflineTerminal description formatting', () {
      const stateWithoutVod = StreamOfflineTerminal();
      expect(stateWithoutVod.description, '主播未开播');

      const stateWithVod = StreamOfflineTerminal(hasVod: true);
      expect(stateWithVod.description, contains('可点击观看录播'));
    });

    test('AuthOrSignatureExpiredTerminal supports re-fetch & login prompt', () {
      const loginState = AuthOrSignatureExpiredTerminal(
        siteId: 'bilibili',
        requiresLogin: true,
      );
      expect(loginState.description, contains('重新扫码登录'));

      const signState = AuthOrSignatureExpiredTerminal(
        siteId: 'douyu',
        requiresLogin: false,
      );
      expect(signState.description, contains('更新解析规则'));
    });

    test('NetworkTransientTerminal supports retry & CDN suggestions', () {
      const retryState = NetworkTransientTerminal(
        retryAttempt: 2,
        hasAlternativeCdn: false,
      );
      expect(retryState.description, contains('正在重试 (2)'));

      const cdnState = NetworkTransientTerminal(
        retryAttempt: 1,
        hasAlternativeCdn: true,
        suggestedCdnIndex: 2,
      );
      expect(cdnState.description, contains('切换备用 CDN'));
    });

    test('DecoderBudgetExhaustedTerminal provides graceful degradation info', () {
      const state = DecoderBudgetExhaustedTerminal(
        concurrentStreams: 4,
        suggestedFallbackDecoder: DecoderMode.software,
      );
      expect(state.description, contains('自动切换为软解模式'));
    });
  });
}
