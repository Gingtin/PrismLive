import 'dart:async';
import 'dart:convert';

import 'package:live_net/live_net.dart';

/// Health and broadcast status of a live stream URL.
enum StreamHealth {
  /// Stream is actively returning live video data or playlist segments.
  live,

  /// Stream server is online and reachable, but currently idle or not broadcasting
  /// (e.g. HTTP 404/502/503/504, or manifest with zero segments / endlist).
  /// Streams in this state should be retained as temporarily offline, not deleted.
  offline,

  /// Permanent failure: host cannot be resolved, connection refused, or HTTP 410.
  dead,

  /// Probe timed out or status cannot be conclusively determined.
  unknown,
}

/// The result of a stream health probe.
class StreamProbeResult {
  /// Creates a probe result.
  const StreamProbeResult({
    required this.health,
    this.statusCode,
    this.message,
    this.latency,
  });

  /// The evaluated health of the stream.
  final StreamHealth health;

  /// HTTP status code if a response was received.
  final int? statusCode;

  /// Diagnostic or status explanation.
  final String? message;

  /// Response latency.
  final Duration? latency;

  /// Whether the stream is ready for immediate playback.
  bool get isPlayable => health == StreamHealth.live;

  /// Whether the stream is only temporarily unstarted/offline.
  bool get isTemporaryOffline => health == StreamHealth.offline;

  /// Whether the stream is permanently dead.
  bool get isPermanentlyDead => health == StreamHealth.dead;

  @override
  String toString() => 'StreamProbeResult(${health.name}, code=$statusCode, latency=${latency?.inMilliseconds}ms)';
}

/// Lightweight, non-destructive probe for IPTV and live stream URLs.
abstract final class StreamProbe {
  /// Upper bound for a probe request.
  static const Duration defaultProbeTimeout = Duration(seconds: 4);

  /// Probes the stream at [url] using [http].
  static Future<StreamProbeResult> probe(
    LiveHttp http,
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = defaultProbeTimeout,
    CancelToken? cancel,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = LiveRequest(
        site: 'iptv',
        url: url,
        method: 'GET',
        headers: {
          if (headers != null) ...headers,
          'range': 'bytes=0-4096',
          'accept': '*/*',
        },
        timeout: timeout,
        cancel: cancel,
      );
      final response = await http.send(request);
      stopwatch.stop();
      final status = response.status;

      if (status >= 200 && status < 300) {
        final bodyPrefix = utf8.decode(response.bytes.take(4096).toList(), allowMalformed: true);
        if (bodyPrefix.contains('#EXTM3U')) {
          if (bodyPrefix.contains('#EXTINF:')) {
            return StreamProbeResult(
              health: StreamHealth.live,
              statusCode: status,
              latency: stopwatch.elapsed,
              message: 'HLS manifest with active segments',
            );
          }
          if (bodyPrefix.contains('#EXT-X-ENDLIST')) {
            return StreamProbeResult(
              health: StreamHealth.offline,
              statusCode: status,
              latency: stopwatch.elapsed,
              message: 'HLS broadcast ended / standby',
            );
          }
          return StreamProbeResult(
            health: StreamHealth.offline,
            statusCode: status,
            latency: stopwatch.elapsed,
            message: 'HLS manifest currently empty',
          );
        }
        return StreamProbeResult(
          health: StreamHealth.live,
          statusCode: status,
          latency: stopwatch.elapsed,
          message: 'Stream online and responding',
        );
      }

      if (status == 404 || status == 502 || status == 503 || status == 504) {
        return StreamProbeResult(
          health: StreamHealth.offline,
          statusCode: status,
          latency: stopwatch.elapsed,
          message: 'Stream not pushed / room idle ($status)',
        );
      }

      if (status == 410) {
        return StreamProbeResult(
          health: StreamHealth.dead,
          statusCode: status,
          latency: stopwatch.elapsed,
          message: 'Stream permanently removed (410 Gone)',
        );
      }

      if (status == 401 || status == 403) {
        return StreamProbeResult(
          health: StreamHealth.offline,
          statusCode: status,
          latency: stopwatch.elapsed,
          message: 'Access restricted or auth expired ($status)',
        );
      }

      return StreamProbeResult(
        health: StreamHealth.unknown,
        statusCode: status,
        latency: stopwatch.elapsed,
        message: 'HTTP $status',
      );
    } on Object catch (error) {
      stopwatch.stop();
      final msg = error.toString().toLowerCase();
      if (msg.contains('resolve') ||
          msg.contains('not known') ||
          msg.contains('getaddrinfo') ||
          msg.contains('connection refused') ||
          msg.contains('no route to host')) {
        return StreamProbeResult(
          health: StreamHealth.dead,
          latency: stopwatch.elapsed,
          message: 'Host unreachable or DNS failed',
        );
      }
      if (msg.contains('timeout') || msg.contains('timed out')) {
        return StreamProbeResult(
          health: StreamHealth.unknown,
          latency: stopwatch.elapsed,
          message: 'Connection timed out',
        );
      }
      return StreamProbeResult(
        health: StreamHealth.offline,
        latency: stopwatch.elapsed,
        message: 'Network error: $error',
      );
    }
  }
}
