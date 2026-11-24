import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

void main() {
  group('IptvSmartExtractor', () {
    test('extracts double-colon formatted links (user input format)', () {
      const input = '''
偶遇::http://api.hclyz.com:81/mf/jsonouyu.txt
依依::http://api.hclyz.com:81/mf/jsonyiyi.txt
夜色::http://api.hclyz.com:81/mf/jsonyese.txt
亚米::http://api.hclyz.com:81/mf/jsonyami.txt
''';
      final sources = IptvSmartExtractor.extract(input);
      expect(sources, hasLength(4));
      expect(sources[0].name, '偶遇');
      expect(sources[0].url, 'http://api.hclyz.com:81/mf/jsonouyu.txt');
      expect(sources[1].name, '依依');
      expect(sources[1].url, 'http://api.hclyz.com:81/mf/jsonyiyi.txt');
      expect(sources[2].name, '夜色');
      expect(sources[2].url, 'http://api.hclyz.com:81/mf/jsonyese.txt');
      expect(sources[3].name, '亚米');
      expect(sources[3].url, 'http://api.hclyz.com:81/mf/jsonyami.txt');
    });

    test('extracts comma, pipe, dollar and space separated lines', () {
      const input = r'''
1. CCTV1,http://example.com/cctv1.m3u8
02、CCTV2，http://example.com/cctv2.m3u8
[3] CCTV3|http://example.com/cctv3.m3u8
- CCTV4$http://example.com/cctv4.m3u8
【湖南卫视】 http://example.com/hunan.flv
''';
      final sources = IptvSmartExtractor.extract(input);
      expect(sources, hasLength(5));
      expect(sources[0].name, 'CCTV1');
      expect(sources[0].url, 'http://example.com/cctv1.m3u8');
      expect(sources[1].name, 'CCTV2');
      expect(sources[1].url, 'http://example.com/cctv2.m3u8');
      expect(sources[2].name, 'CCTV3');
      expect(sources[2].url, 'http://example.com/cctv3.m3u8');
      expect(sources[3].name, 'CCTV4');
      expect(sources[3].url, 'http://example.com/cctv4.m3u8');
      expect(sources[4].name, '湖南卫视');
      expect(sources[4].url, 'http://example.com/hunan.flv');
    });

    test('extractSingle extracts first matching source or clean single line', () {
      final single = IptvSmartExtractor.extractSingle('偶遇::http://api.hclyz.com:81/mf/jsonouyu.txt');
      expect(single, isNotNull);
      expect(single!.name, '偶遇');
      expect(single.url, 'http://api.hclyz.com:81/mf/jsonouyu.txt');
    });

    test('derives fallback name from url when no name is provided', () {
      const input = 'http://example.com/live/my_super_channel.m3u8';
      final sources = IptvSmartExtractor.extract(input);
      expect(sources, hasLength(1));
      expect(sources.single.name, 'my_super_channel');
      expect(sources.single.url, 'http://example.com/live/my_super_channel.m3u8');
    });

    test('deduplicates identical URLs', () {
      const input = '''
源1::http://example.com/live.m3u8
源2::http://example.com/live.m3u8
''';
      final sources = IptvSmartExtractor.extract(input);
      expect(sources, hasLength(1));
      expect(sources.single.name, '源1');
    });

    test('detects JSON format even when url ends in .txt (e.g. jsonouyu.txt)', () {
      const jsonContent = '{"zhubo": [{"title": "Test", "address": "http://f/live.flv"}]}';
      final format = detectPlaylistFormat(jsonContent, path: 'http://api.hclyz.com:81/mf/jsonouyu.txt');
      expect(format, IptvPlaylistFormat.json);

      final parseResult = parsePlaylist(jsonContent, format!);
      expect(parseResult.entries, hasLength(1));
      expect(parseResult.entries.single.name, 'Test');
      expect(parseResult.entries.single.streamUrl, 'http://f/live.flv');
    });
  });
}
