import 'dart:async';
import 'dart:convert';

import 'package:live_iptv/src/model.dart';
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
  const new({
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

/// Progress update during a batch stream health probe.
final class StreamProbeProgress {
  /// Creates a progress update.
  const new({
    required this.completed,
    required this.total,
    required this.liveCount,
    required this.offlineCount,
    required this.deadCount,
    this.currentChannel,
    this.currentResult,
  });

  /// Total number of streams probed so far.
  final int completed;

  /// Total count of streams to probe.
  final int total;

  /// Number of streams verified online and actively broadcasting.
  final int liveCount;

  /// Number of streams online but temporarily idle/unstarted.
  final int offlineCount;

  /// Number of streams permanently unreachable or invalid.
  final int deadCount;

  /// The channel currently being or just probed.
  final IptvChannel? currentChannel;

  /// Probe result for [currentChannel].
  final StreamProbeResult? currentResult;

  /// Progress fraction in 0.0 .. 1.0.
  double get fraction => total > 0 ? completed / total : 0.0;
}

/// Lightweight, non-destructive probe for IPTV and live stream URLs.
abstract final class StreamProbe {
  /// Upper bound for a probe request.
  static const Duration defaultProbeTimeout = Duration(seconds: 4);

  static final Map<String, ({StreamProbeResult result, DateTime timestamp})> _cache = {};

  /// Default cache time-to-live for stream probe results.
  static const Duration defaultCacheTtl = Duration(minutes: 5);

  /// Looks up cached probe result if fresh.
  static StreamProbeResult? getCached(String url, {Duration ttl = defaultCacheTtl}) {
    final entry = _cache[url];
    if (entry != null && DateTime.now().difference(entry.timestamp) < ttl) {
      return entry.result;
    }
    return null;
  }

  /// Records a result in the probe cache.
  static void cacheResult(String url, StreamProbeResult result) {
    _cache[url] = (result: result, timestamp: DateTime.now());
  }

  /// Clears the stream probe cache.
  static void clearCache() => _cache.clear();

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
        headers: {
          ...?headers,
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

  /// Probes [channels] concurrently with worker limit [concurrency].
  /// Yields a [StreamProbeProgress] after each channel finishes probing.
  static Stream<StreamProbeProgress> probeChannels(
    LiveHttp http,
    List<IptvChannel> channels, {
    int concurrency = 6,
    Duration timeout = const Duration(seconds: 3),
    CancelToken? cancel,
  }) async* {
    if (channels.isEmpty) return;

    final controller = StreamController<StreamProbeProgress>();
    var completed = 0;
    var liveCount = 0;
    var offlineCount = 0;
    var deadCount = 0;
    var queueIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (cancel?.isCancelled == true) break;
        final int index;
        if (queueIndex >= channels.length) break;
        index = queueIndex++;
        final channel = channels[index];
        final urlStr = channel.entry.streamUrl.trim();
        final uri = Uri.tryParse(urlStr);

        StreamProbeResult result;
        if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
          result = const StreamProbeResult(
            health: StreamHealth.dead,
            message: 'Invalid URL scheme',
          );
        } else {
          try {
            result = await probe(http, uri, timeout: timeout, cancel: cancel);
          } on Object catch (e) {
            result = StreamProbeResult(
              health: StreamHealth.dead,
              message: e.toString(),
            );
          }
        }
        cacheResult(urlStr, result);

        completed++;
        switch (result.health) {
          case StreamHealth.live:
            liveCount++;
          case StreamHealth.offline:
            offlineCount++;
          case StreamHealth.dead:
            deadCount++;
          case StreamHealth.unknown:
            offlineCount++;
        }

        controller.add(StreamProbeProgress(
          completed: completed,
          total: channels.length,
          liveCount: liveCount,
          offlineCount: offlineCount,
          deadCount: deadCount,
          currentChannel: channel,
          currentResult: result,
        ));
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, channels.length),
      (_) => worker(),
    );

    unawaited(Future.wait(workers).whenComplete(controller.close));

    yield* controller.stream;
  }

  static int _healthRank(StreamHealth? health) => switch (health) {
    StreamHealth.live => 0,
    StreamHealth.offline => 1,
    StreamHealth.unknown || null => 2,
    StreamHealth.dead => 3,
  };

  /// Sorts channels by availability and response latency:
  /// 1. Playable (`live`) first, ordered by lowest latency.
  /// 2. Temporarily offline (`offline`), maintaining original relative order.
  /// 3. Unknown, maintaining original relative order.
  /// 4. Permanently dead (`dead`) at the bottom.
  static List<IptvChannel> sortChannelsByHealth(
    List<IptvChannel> channels,
    Map<String, StreamProbeResult> results,
  ) {
    return List<IptvChannel>.of(channels)..sort((a, b) {
      final resA = results[a.entry.streamUrl.trim()] ?? getCached(a.entry.streamUrl.trim());
      final resB = results[b.entry.streamUrl.trim()] ?? getCached(b.entry.streamUrl.trim());

      final rankA = _healthRank(resA?.health);
      final rankB = _healthRank(resB?.health);
      if (rankA != rankB) return rankA.compareTo(rankB);

      if (resA?.health == StreamHealth.live && resB?.health == StreamHealth.live) {
        final latA = resA?.latency?.inMilliseconds ?? 99999;
        final latB = resB?.latency?.inMilliseconds ?? 99999;
        return latA.compareTo(latB);
      }
      return 0;
    });
  }

  /// Filters out permanently dead channels.
  static List<IptvChannel> filterDeadChannels(
    List<IptvChannel> channels,
    Map<String, StreamProbeResult> results,
  ) => channels.where((c) {
    final res = results[c.entry.streamUrl.trim()] ?? getCached(c.entry.streamUrl.trim());
    return res?.health != StreamHealth.dead;
  }).toList();

  /// Quickly probes a list of stream URLs concurrently and returns them sorted by responsiveness.
  static Future<List<String>> sortLinesBySpeed(
    LiveHttp http,
    List<String> urls, {
    Duration timeout = const Duration(milliseconds: 1600),
    CancelToken? cancel,
  }) async {
    if (urls.length <= 1) return urls;

    final results = <String, StreamProbeResult>{};
    await Future.wait(urls.map((u) async {
      final cached = getCached(u);
      if (cached != null) {
        results[u] = cached;
        return;
      }
      final uri = Uri.tryParse(u);
      if (uri == null) return;
      try {
        final r = await probe(http, uri, timeout: timeout, cancel: cancel);
        results[u] = r;
        cacheResult(u, r);
      } on Object catch (_) {}
    }));

    return List<String>.of(urls)..sort((a, b) {
      final resA = results[a];
      final resB = results[b];
      final rankA = _healthRank(resA?.health);
      final rankB = _healthRank(resB?.health);
      if (rankA != rankB) return rankA.compareTo(rankB);
      final latA = resA?.latency?.inMilliseconds ?? 99999;
      final latB = resB?.latency?.inMilliseconds ?? 99999;
      return latA.compareTo(latB);
    });
  }
}
