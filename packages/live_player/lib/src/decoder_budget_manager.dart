import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';

/// Four precise playback terminal error states (PureLive NextGen Spec §5.1).
///
/// Ensures exhaustive attribution instead of vague "加载失败" toasts.
sealed class PlaybackTerminalState {
  const new();

  /// Human-readable diagnostic description in Chinese.
  String get description;
}

/// Stream is offline (Anchor not streaming).
final class StreamOfflineTerminal extends PlaybackTerminalState {
  /// Creates an offline terminal state.
  const new({this.lastLiveTime, this.hasVod = false});

  /// The timestamp of the last known broadcast.
  final DateTime? lastLiveTime;

  /// Whether recorded VOD replays are available for this anchor.
  final bool hasVod;

  @override
  String get description => '主播未开播${hasVod ? ' (可点击观看录播)' : ''}';
}

/// Authentication or anti-hotlinking signature expired (Cookie or Wbi invalid).
final class AuthOrSignatureExpiredTerminal extends PlaybackTerminalState {
  /// Creates an auth or signature expiration state.
  const new({
    required this.siteId,
    required this.requiresLogin,
    this.message,
  });

  /// The platform identifier.
  final String siteId;

  /// Whether the user needs to re-authenticate or scan QR code.
  final bool requiresLogin;

  /// Additional diagnostic details from the platform.
  final String? message;

  @override
  String get description => requiresLogin
      ? '登录凭据已过期，请重新扫码登录'
      : '平台反爬规则已更新，请在设置中一键更新解析规则';
}

/// Transient network failure / CDN congestion (eligible for backoff retry & CDN switch).
final class NetworkTransientTerminal extends PlaybackTerminalState {
  /// Creates a transient network failure state.
  const new({
    required this.retryAttempt,
    required this.hasAlternativeCdn,
    this.suggestedCdnIndex,
  });

  /// Current retry count.
  final int retryAttempt;

  /// Whether alternative CDN lines are available.
  final bool hasAlternativeCdn;

  /// Index of the suggested alternative CDN line.
  final int? suggestedCdnIndex;

  @override
  String get description => hasAlternativeCdn
      ? '当前线路网络拥塞，建议切换备用 CDN 线路'
      : '网络连接超时，正在重试 ($retryAttempt)...';
}

/// Hardware decoder budget exhausted (Too many concurrent hardware decoders / OOM risk).
final class DecoderBudgetExhaustedTerminal extends PlaybackTerminalState {
  /// Creates a decoder budget exhaustion state.
  const new({
    required this.concurrentStreams,
    required this.suggestedFallbackDecoder,
  });

  /// Number of concurrently active streams.
  final int concurrentStreams;

  /// Recommended fallback decoder mode.
  final DecoderMode suggestedFallbackDecoder;

  @override
  String get description => '硬件解码器配额超限，已自动切换为软解模式以防崩溃';
}

/// Multiview hardware decoder budget scheduler (PureLive NextGen Spec §5.2).
///
/// MediaCodec hardware decoders on Android SoC and TV boxes are physically limited
/// to 2-3 concurrent streams. This scheduler guarantees that the active focused
/// stream receives full hardware acceleration while secondary monitoring streams
/// are safely throttled to avoid OOM crashes.
class DecoderBudgetManager {
  /// Creates a decoder budget manager.
  new({
    int? maxHardwareDecoders,
    this.onBudgetNotice,
  }) : maxHardwareDecoders = maxHardwareDecoders ?? defaultMaxDecoders;

  /// Callback when budget adjustment occurs.
  final void Function(String message)? onBudgetNotice;

  /// Maximum concurrent hardware decoders allowed on this device.
  final int maxHardwareDecoders;

  /// Platform default budget: 2 on Android/iOS/TV, 8 on Desktop.
  static int get defaultMaxDecoders {
    if (kIsWeb) return 4;
    return (Platform.isAndroid || Platform.isIOS) ? 2 : 8;
  }

  final Set<int> _activeHardwareCells = {};

  /// The currently focused / audible cell.
  int? focusedCellId;

  /// Determines whether [cellId] should use hardware decoding under budget constraints.
  DecoderMode allocateDecoderForCell(int cellId, {bool isAudible = false}) {
    if (isAudible || cellId == focusedCellId) {
      _activeHardwareCells.add(cellId);
      return DecoderMode.hardware;
    }

    if (_activeHardwareCells.length < maxHardwareDecoders) {
      _activeHardwareCells.add(cellId);
      return DecoderMode.hardware;
    }

    // Budget exceeded: fallback secondary screen to software decoding
    onBudgetNotice?.call('硬件解码器达到上限，次要分屏已切换为软解');
    return DecoderMode.software;
  }

  /// Releases decoder allocation when a cell stops or is removed.
  void releaseCell(int cellId) {
    _activeHardwareCells.remove(cellId);
  }

  /// Clears all allocated decoders.
  void reset() {
    _activeHardwareCells.clear();
    focusedCellId = null;
  }
}
