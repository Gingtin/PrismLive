import 'dart:convert';

import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

final class _MockProbeHttp implements LiveHttp {
  new(this.responder);

  final Future<LiveResponse> Function(LiveRequest request) responder;

  @override
  Future<LiveResponse> send(LiveRequest request) => responder(request);

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  group('StreamProbe health triage', () {
    test('reports live for HLS manifest with active segments', () async {
      final http = _MockProbeHttp((req) async {
        const hls = '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXTINF:10.0,\nseg1.ts\n';
        return LiveResponse(status: 200, bytes: utf8.encode(hls), url: req.url);
      });

      final result = await StreamProbe.probe(http, Uri.parse('http://example.com/live.m3u8'));
      expect(result.health, StreamHealth.live);
      expect(result.isPlayable, isTrue);
      expect(result.isTemporaryOffline, isFalse);
    });

    test('reports offline for HLS manifest with ENDLIST and no segments', () async {
      final http = _MockProbeHttp((req) async {
        const hls = '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-ENDLIST\n';
        return LiveResponse(status: 200, bytes: utf8.encode(hls), url: req.url);
      });

      final result = await StreamProbe.probe(http, Uri.parse('http://example.com/idle.m3u8'));
      expect(result.health, StreamHealth.offline);
      expect(result.isTemporaryOffline, isTrue);
      expect(result.isPlayable, isFalse);
    });

    test('reports offline for HTTP 404/503 (anchor offline / CDN idle)', () async {
      final http404 = _MockProbeHttp((req) async {
        return LiveResponse(status: 404, bytes: const [], url: req.url);
      });
      final res404 = await StreamProbe.probe(http404, Uri.parse('http://example.com/room404.flv'));
      expect(res404.health, StreamHealth.offline);
      expect(res404.isTemporaryOffline, isTrue);
      expect(res404.isPermanentlyDead, isFalse);

      final http503 = _MockProbeHttp((req) async {
        return LiveResponse(status: 503, bytes: const [], url: req.url);
      });
      final res503 = await StreamProbe.probe(http503, Uri.parse('http://example.com/room503.m3u8'));
      expect(res503.health, StreamHealth.offline);
      expect(res503.isTemporaryOffline, isTrue);
    });

    test('reports dead for HTTP 410 or DNS resolution errors', () async {
      final http410 = _MockProbeHttp((req) async {
        return LiveResponse(status: 410, bytes: const [], url: req.url);
      });
      final res410 = await StreamProbe.probe(http410, Uri.parse('http://example.com/dead.m3u8'));
      expect(res410.health, StreamHealth.dead);
      expect(res410.isPermanentlyDead, isTrue);

      final httpDnsFail = _MockProbeHttp((req) async {
        throw const TransportFailure('iptv', TransportReason.connect, 'dns resolve failed');
      });
      final resDns = await StreamProbe.probe(httpDnsFail, Uri.parse('http://bad.domain/live.m3u8'));
      expect(resDns.health, StreamHealth.dead);
      expect(resDns.isPermanentlyDead, isTrue);
    });

    test('cacheResult and getCached maintain probe TTL', () {
      StreamProbe.clearCache();
      const url = 'http://example.com/cached.m3u8';
      expect(StreamProbe.getCached(url), isNull);

      const res = StreamProbeResult(health: StreamHealth.live, latency: Duration(milliseconds: 50));
      StreamProbe.cacheResult(url, res);
      expect(StreamProbe.getCached(url), isNotNull);
      expect(StreamProbe.getCached(url)!.latency!.inMilliseconds, 50);

      StreamProbe.clearCache();
      expect(StreamProbe.getCached(url), isNull);
    });

    test('sortChannelsByHealth places live channels first sorted by latency', () {
      final c1 = IptvChannel(
        id: '1',
        playlistId: 'p',
        entry: IptvEntry(name: 'Ch1', streamUrl: 'http://example.com/dead.m3u8'),
      );
      final c2 = IptvChannel(
        id: '2',
        playlistId: 'p',
        entry: IptvEntry(name: 'Ch2', streamUrl: 'http://example.com/slow.m3u8'),
      );
      final c3 = IptvChannel(
        id: '3',
        playlistId: 'p',
        entry: IptvEntry(name: 'Ch3', streamUrl: 'http://example.com/fast.m3u8'),
      );

      final results = {
        'http://example.com/dead.m3u8': const StreamProbeResult(health: StreamHealth.dead),
        'http://example.com/slow.m3u8': const StreamProbeResult(health: StreamHealth.live, latency: Duration(milliseconds: 300)),
        'http://example.com/fast.m3u8': const StreamProbeResult(health: StreamHealth.live, latency: Duration(milliseconds: 60)),
      };

      final sorted = StreamProbe.sortChannelsByHealth([c1, c2, c3], results);
      expect(sorted.map((c) => c.id).toList(), ['3', '2', '1']);

      final filtered = StreamProbe.filterDeadChannels([c1, c2, c3], results);
      expect(filtered.map((c) => c.id).toList(), ['2', '3']);
    });

    test('sortLinesBySpeed orders URLs by latency', () async {
      StreamProbe.clearCache();
      final http = _MockProbeHttp((req) async {
        final ms = req.url.path.contains('fast') ? 30 : 200;
        await Future<void>.delayed(Duration(milliseconds: ms));
        return LiveResponse(
          status: 200,
          bytes: utf8.encode('#EXTM3U\n#EXTINF:10,\ns.ts\n'),
          url: req.url,
        );
      });

      final lines = ['http://example.com/slow.m3u8', 'http://example.com/fast.m3u8'];
      final sorted = await StreamProbe.sortLinesBySpeed(http, lines);
      expect(sorted, isNotEmpty);
    });
  });
}
