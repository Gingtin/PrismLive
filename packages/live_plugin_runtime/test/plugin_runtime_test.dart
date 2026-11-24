import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_plugin_runtime/live_plugin_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('Live Plugin Runtime Tests', () {
    late Uint8List testSeed;
    late ({Uint8List secretKey, Uint8List publicKey}) testKeys;

    setUp(() {
      testSeed = Uint8List(32)..fillRange(0, 32, 99);
      testKeys = Ed25519.generateKeyPairFromSeed(testSeed);
    });

    test('PluginManifest parses and converts to SourceDescriptor accurately', () {
      final json = {
        'id': 'testlive',
        'name': 'Test Live Platform',
        'version': '1.2.0',
        'author': 'PrismLive Team',
        'allowedDomains': ['api.testlive.com', '*.cdn.testlive.com'],
        'region': 'domestic',
        'categories': ['game', 'entertainment'],
        'networkMode': 'proxyRecommended',
        'isNsfw': false,
        'aliases': ['tl', 'testlive'],
      };

      final manifest = PluginManifest.fromJson(json);
      expect(manifest.id, equals('testlive'));
      expect(manifest.name, equals('Test Live Platform'));
      expect(manifest.allowedDomains, contains('api.testlive.com'));
      expect(manifest.networkMode, equals(NetworkMode.proxyRecommended));
      expect(manifest.isNsfw, isFalse);

      final descriptor = manifest.toSourceDescriptor();
      expect(descriptor.id, equals('testlive'));
      expect(descriptor.supportStatus, equals(SourceSupportStatus.ready));
      expect(descriptor.networkMode, equals(NetworkMode.proxyRecommended));
    });

    test('DomainWhitelistValidator strictly checks host authorization', () {
      final allowed = ['api.huajiao.com', '*.live.qq.com', '.stripchat.com'];

      expect(
        DomainWhitelistValidator.isAllowed(Uri.parse('https://api.huajiao.com/v1/room'), allowed),
        isTrue,
      );
      expect(
        DomainWhitelistValidator.isAllowed(Uri.parse('https://stream.live.qq.com/live/1'), allowed),
        isTrue,
      );
      expect(
        DomainWhitelistValidator.isAllowed(Uri.parse('https://cdn.stripchat.com/hls/1.m3u8'), allowed),
        isTrue,
      );

      // Unauthorized domains must be rejected
      expect(
        DomainWhitelistValidator.isAllowed(Uri.parse('https://evil.attacker.com/steal'), allowed),
        isFalse,
      );
      expect(
        DomainWhitelistValidator.isAllowed(Uri.parse('https://notqq.com/v1'), allowed),
        isFalse,
      );
    });

    test('PluginSandbox verifies valid Ed25519 signature and executes 4-method contract', () async {
      const scriptCode = '''
// PrismLive Verified Plugin
export default {
  author: "PrismLive",
  version: "1.0.0"
};
''';
      final signature = LivePluginManager.signScript(scriptCode, testKeys.secretKey);
      final pubKeyHex = Ed25519.bytesToHex(testKeys.publicKey);

      final manifest = PluginManifest(
        id: 'huajiao',
        name: '花椒直播',
        version: '1.0.0',
        author: 'Official',
        allowedDomains: const ['api.huajiao.com'],
        signature: signature,
        publicKey: pubKeyHex,
      );

      final manager = LivePluginManager();
      final site = manager.loadPlugin(manifest: manifest, script: scriptCode);

      expect(site.id, equals('huajiao'));
      expect(site.name, equals('花椒直播'));
      expect(site.sandbox.isVerified, isTrue);

      // Contract 1: meta()
      final meta = await site.sandbox.meta();
      expect(meta.id, equals('huajiao'));

      // Contract 2: getRoomInfo()
      final room = await site.getRoomDetail(roomId: '998877');
      expect(room.roomId, equals('998877'));
      expect(room.platform, equals('huajiao'));
      expect(room.liveStatus, equals(LiveStatus.live));

      // Contract 3: getPlayQualities()
      final qualities = await site.getPlayQualities(detail: room);
      expect(qualities.isNotEmpty, isTrue);
      expect(qualities.first.quality, equals('原画'));
      final urls = await site.getPlayUrls(detail: room, quality: qualities.first);
      expect(urls.isNotEmpty, isTrue);

      // Contract 4: getDanmakuConfig()
      final danmakuConfig = await site.sandbox.getDanmakuConfig('998877');
      expect(danmakuConfig['platform'], equals('huajiao'));
    });

    test('PluginSandbox rejects script with forbidden tokens (eval, process, etc.)', () {
      const maliciousScript = '''
function hack() {
  return eval("1 + 1");
}
''';
      final signature = LivePluginManager.signScript(maliciousScript, testKeys.secretKey);
      final manifest = PluginManifest(
        id: 'malicious',
        name: 'Malicious Plugin',
        version: '1.0.0',
        author: 'Bad Actor',
        signature: signature,
        publicKey: Ed25519.bytesToHex(testKeys.publicKey),
      );

      final manager = LivePluginManager();
      expect(
        () => manager.loadPlugin(manifest: manifest, script: maliciousScript),
        throwsA(isA<PluginSecurityException>()),
      );
    });

    test('PluginSandbox rejects tampered script or invalid signature', () {
      const originalScript = 'const x = 1;';
      final signature = LivePluginManager.signScript(originalScript, testKeys.secretKey);

      const tamperedScript = 'const x = 2;'; // Altered!
      final manifest = PluginManifest(
        id: 'tampered',
        name: 'Tampered Plugin',
        version: '1.0.0',
        author: 'Bad Actor',
        signature: signature,
        publicKey: Ed25519.bytesToHex(testKeys.publicKey),
      );

      final manager = LivePluginManager();
      expect(
        () => manager.loadPlugin(manifest: manifest, script: tamperedScript),
        throwsA(isA<PluginSecurityException>()),
      );
    });

    test('LivePluginManager falls back to cached verified version when update is tampered', () {
      const v1Script = 'const version = 1;';
      final v1Signature = LivePluginManager.signScript(v1Script, testKeys.secretKey);
      final manifestV1 = PluginManifest(
        id: 'kuaishou_plugin',
        name: '快手扩展',
        version: '1.0.0',
        author: 'Official',
        signature: v1Signature,
        publicKey: Ed25519.bytesToHex(testKeys.publicKey),
      );

      final manager = LivePluginManager();
      final siteV1 = manager.loadPlugin(manifest: manifestV1, script: v1Script);
      expect(siteV1.manifest.version, equals('1.0.0'));

      // Now load tampered v2
      const v2Tampered = 'const version = 2; /* tampered */';
      final manifestV2 = PluginManifest(
        id: 'kuaishou_plugin',
        name: '快手扩展',
        version: '2.0.0',
        author: 'Official',
        signature: 'deadbeef' * 8, // Invalid signature
        publicKey: Ed25519.bytesToHex(testKeys.publicKey),
      );

      // Loading tampered v2 logs warning and returns fallback v1
      final fallbackSite = manager.loadPlugin(manifest: manifestV2, script: v2Tampered);
      expect(fallbackSite.manifest.version, equals('1.0.0'));
      expect(manager.getSite('kuaishou_plugin')?.manifest.version, equals('1.0.0'));
    });
  });
}
