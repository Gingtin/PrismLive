import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_plugin_runtime/live_plugin_runtime.dart';

void main() {
  final seed = Uint8List.fromList(
    sha256.convert(utf8.encode('PrismLive-Master-Official-Signing-Seed-2026')).bytes,
  );
  final keyPair = Ed25519.generateKeyPairFromSeed(seed);
  final pubKeyHex = Ed25519.bytesToHex(keyPair.publicKey);

  final pluginsDir = Directory('plugins/sites');
  if (!pluginsDir.existsSync()) {
    pluginsDir.createSync(recursive: true);
  }

  final pluginConfigs = [
    {
      'id': 'huajiao',
      'name': '花椒直播',
      'domain': 'api.huajiao.com',
      'region': 'domestic',
      'categories': ['entertainment'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'qqsports',
      'name': '企鹅体育',
      'domain': 'live.qq.com',
      'region': 'domestic',
      'categories': ['sports'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'cctvlive',
      'name': '央视频/咪咕公开流',
      'domain': 'miguvideo.com',
      'region': 'domestic',
      'categories': ['sports', 'news', 'fastTv'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'facebook',
      'name': 'Facebook Live',
      'domain': 'facebook.com',
      'region': 'international',
      'categories': ['entertainment', 'lifestyle'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'rumble',
      'name': 'Rumble',
      'domain': 'rumble.com',
      'region': 'international',
      'categories': ['news', 'entertainment'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'dlive',
      'name': 'DLive',
      'domain': 'dlive.tv',
      'region': 'international',
      'categories': ['game', 'entertainment'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'vimeo',
      'name': 'Vimeo Live',
      'domain': 'vimeo.com',
      'region': 'international',
      'categories': ['entertainment', 'lifestyle'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'dailymotion',
      'name': 'Dailymotion',
      'domain': 'dailymotion.com',
      'region': 'international',
      'categories': ['news', 'entertainment'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'openrec',
      'name': 'OPENREC.tv',
      'domain': 'openrec.tv',
      'region': 'eastAsia',
      'categories': ['game'],
      'networkMode': 'proxyRecommended',
      'isNsfw': false,
    },
    {
      'id': 'mirrativ',
      'name': 'Mirrativ',
      'domain': 'mirrativ.com',
      'region': 'eastAsia',
      'categories': ['game'],
      'networkMode': 'proxyRecommended',
      'isNsfw': false,
    },
    {
      'id': 'nimotv',
      'name': 'Nimo TV',
      'domain': 'nimo.tv',
      'region': 'southeastAsia',
      'categories': ['game'],
      'networkMode': 'proxyRecommended',
      'isNsfw': false,
    },
    {
      'id': 'wavelive',
      'name': 'WAVE',
      'domain': 'wave.live',
      'region': 'eastAsia',
      'categories': ['audio', 'entertainment'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'plutotv',
      'name': 'Pluto TV',
      'domain': 'pluto.tv',
      'region': 'international',
      'categories': ['fastTv', 'news', 'entertainment'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'mixcloud',
      'name': 'Mixcloud Live',
      'domain': 'mixcloud.com',
      'region': 'international',
      'categories': ['audio'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'radiko',
      'name': 'radiko',
      'domain': 'radiko.jp',
      'region': 'eastAsia',
      'categories': ['audio'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'ardzdf',
      'name': 'ARD / ZDF Mediathek',
      'domain': 'ardmediathek.de',
      'region': 'international',
      'categories': ['news', 'fastTv'],
      'networkMode': 'proxyRequired',
      'isNsfw': false,
    },
    {
      'id': 'nhkworld',
      'name': 'NHK World-Japan',
      'domain': 'nhk.or.jp',
      'region': 'eastAsia',
      'categories': ['news', 'fastTv'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'france24',
      'name': 'France 24',
      'domain': 'france24.com',
      'region': 'international',
      'categories': ['news', 'fastTv'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'aljazeera',
      'name': 'Al Jazeera English',
      'domain': 'aljazeera.com',
      'region': 'international',
      'categories': ['news', 'fastTv'],
      'networkMode': 'direct',
      'isNsfw': false,
    },
    {
      'id': 'chaturbate',
      'name': 'Chaturbate',
      'domain': 'chaturbate.com',
      'region': 'international',
      'categories': ['adult'],
      'networkMode': 'proxyRequired',
      'isNsfw': true,
    },
    {
      'id': 'stripchat',
      'name': 'Stripchat',
      'domain': 'stripchat.com',
      'region': 'international',
      'categories': ['adult'],
      'networkMode': 'proxyRequired',
      'isNsfw': true,
    },
    {
      'id': 'bongacams',
      'name': 'BongaCams',
      'domain': 'bongacams.com',
      'region': 'international',
      'categories': ['adult'],
      'networkMode': 'proxyRequired',
      'isNsfw': true,
    },
    {
      'id': 'cam4',
      'name': 'Cam4',
      'domain': 'cam4.com',
      'region': 'international',
      'categories': ['adult'],
      'networkMode': 'proxyRequired',
      'isNsfw': true,
    },
    {
      'id': 'myfreecams',
      'name': 'MyFreeCams',
      'domain': 'myfreecams.com',
      'region': 'international',
      'categories': ['adult'],
      'networkMode': 'proxyRequired',
      'isNsfw': true,
    },
  ];

  final manager = LivePluginManager();
  var successCount = 0;

  for (final conf in pluginConfigs) {
    final id = conf['id']! as String;
    final name = conf['name']! as String;
    final domain = conf['domain']! as String;
    final isNsfw = conf['isNsfw']! as bool;

    final script = '''
// PrismLive Official Verified Plugin: $name ($id)
export default {
  author: "PrismLive Official",
  version: "1.0.0",
  id: "$id",
  domain: "$domain"
};
''';

    final signature = LivePluginManager.signScript(script, keyPair.secretKey);

    final manifestMap = {
      'id': id,
      'name': name,
      'version': '1.0.0',
      'author': 'PrismLive Official',
      'allowedDomains': [domain, '*.$domain'],
      'signature': signature,
      'publicKey': pubKeyHex,
      'region': conf['region'],
      'categories': conf['categories'],
      'networkMode': conf['networkMode'],
      'isNsfw': isNsfw,
      'entryPoint': 'index.js',
    };

    final siteDir = Directory('plugins/sites/$id');
    if (!siteDir.existsSync()) {
      siteDir.createSync(recursive: true);
    }

    File('plugins/sites/$id/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifestMap),
    );
    File('plugins/sites/$id/index.js').writeAsStringSync(script);

    final manifest = PluginManifest.fromJson(manifestMap);
    final site = manager.loadPlugin(manifest: manifest, script: script);
    if (site.sandbox.isVerified) {
      successCount++;
    }
  }

  stdout.writeln(
    'Successfully generated, signed and verified $successCount / ${pluginConfigs.length} plugins in plugins/sites/',
  );
}
