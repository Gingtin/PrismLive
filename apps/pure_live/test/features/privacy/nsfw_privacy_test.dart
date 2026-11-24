import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live/features/privacy/nsfw_privacy_manager.dart';

void main() {
  group('NSFW Quadruple Privacy Shield Tests', () {
    final manager = NsfwPrivacyManager.instance;

    const adultIds = [
      SiteIds.chaturbate,
      SiteIds.stripchat,
      SiteIds.bongacams,
      SiteIds.cam4,
      SiteIds.myfreecams,
      SiteIds.camsoda,
      SiteIds.flirt4free,
      SiteIds.streamate,
      SiteIds.xlovecam,
      SiteIds.dreamcam,
      SiteIds.stripchatVr,
      SiteIds.dreamcamVr,
      SiteIds.sexchathu,
    ];

    setUp(() {
      manager
        ..lock()
        ..clearPin();
    });

    test('Hard Invariant #5: isUnlocked strictly defaults to false', () {
      expect(manager.isUnlocked, isFalse);
    });

    test('Zero-exposure invariant: locked manager filters out 100% of NSFW descriptors', () {
      final allDescriptors = SiteIds.descriptors.values.toList();
      final nsfwCountInCatalog = allDescriptors.where((d) => d.isNsfw).length;
      expect(nsfwCountInCatalog, equals(13));

      // When locked, filterDescriptors must return exactly 0 NSFW items
      final filtered = manager.filterDescriptors(allDescriptors);
      final nsfwInFiltered = filtered.where((d) => d.isNsfw).toList();

      expect(nsfwInFiltered, isEmpty);
      expect(filtered.length, equals(allDescriptors.length - nsfwCountInCatalog));

      // Specific known adult sites must never leak in locked state
      for (final adultId in adultIds) {
        expect(
          filtered.any((d) => d.id == adultId),
          isFalse,
          reason: 'Adult platform $adultId leaked in locked state',
        );
      }
    });

    test('Zero-exposure invariant: IptvImporter.curatedPresets has 0 adult / NSFW feeds', () {
      for (final preset in IptvImporter.curatedPresets) {
        final lowerUrl = preset.url.toLowerCase();
        final lowerName = preset.name.toLowerCase();
        final lowerDesc = preset.desc.toLowerCase();

        expect(lowerUrl.contains('xxx'), isFalse, reason: 'URL leaked xxx: ${preset.url}');
        expect(lowerUrl.contains('nsfw'), isFalse, reason: 'URL leaked nsfw: ${preset.url}');
        expect(lowerName.contains('xxx'), isFalse, reason: 'Name leaked xxx: ${preset.name}');
        expect(lowerName.contains('成人'), isFalse, reason: 'Name leaked adult keyword: ${preset.name}');
        expect(lowerDesc.contains('成人'), isFalse, reason: 'Desc leaked adult keyword: ${preset.desc}');
      }
    });

    test('Unlocked state invariant: all 13 adult platforms available with valid properties', () {
      manager.unlockForTesting();
      expect(manager.isUnlocked, isTrue);

      final allDescriptors = SiteIds.descriptors.values.toList();
      final filtered = manager.filterDescriptors(allDescriptors);

      expect(filtered.length, equals(allDescriptors.length));

      for (final adultId in adultIds) {
        final desc = filtered.firstWhere(
          (d) => d.id == adultId,
          orElse: () => throw StateError('Missing adult platform: $adultId'),
        );

        expect(desc.isNsfw, isTrue);
        expect(desc.categories.contains(SourceCategory.adult), isTrue);
        expect(desc.networkMode, equals(NetworkMode.proxyRequired));
        expect(
          [
            SourceSupportStatus.ready,
            SourceSupportStatus.experimental,
            SourceSupportStatus.pluginPending,
          ].contains(desc.supportStatus),
          isTrue,
        );
      }
    });

    test('curatedNsfwPresets invariant: official IPTV adult presets strictly isolated', () {
      expect(IptvImporter.curatedNsfwPresets.length, equals(2));

      final xxxPreset = IptvImporter.curatedNsfwPresets.firstWhere(
        (p) => p.url.contains('xxx.m3u'),
      );
      expect(xxxPreset.isNsfw, isTrue);
      expect(xxxPreset.networkMode, equals(NetworkMode.proxyRequired));
      expect(xxxPreset.url, equals('https://iptv-org.github.io/iptv/categories/xxx.m3u'));

      final fullPreset = IptvImporter.curatedNsfwPresets.firstWhere(
        (p) => p.url.contains('index.nsfw.m3u'),
      );
      expect(fullPreset.isNsfw, isTrue);
      expect(fullPreset.networkMode, equals(NetworkMode.proxyRequired));
      expect(fullPreset.url, equals('https://iptv-org.github.io/iptv/index.nsfw.m3u'));
    });

    test('PIN authentication: SHA-256 with salt correctly validates and rejects invalid PINs', () {
      expect(manager.hasPin, isFalse);

      expect(() => manager.setPin('123'), throwsArgumentError);
      expect(() => manager.setPin('abcdef'), throwsArgumentError);

      manager.setPin('654321');
      expect(manager.hasPin, isTrue);

      expect(manager.verifyPin('654321'), isTrue);
      expect(manager.verifyPin('123456'), isFalse);
      expect(manager.verifyPin('000000'), isFalse);

      manager.clearPin();
      expect(manager.hasPin, isFalse);
      expect(manager.verifyPin('654321'), isFalse);
    });

    test('Zero-trace memory storage & BossKey instant lock: tokens, thumbnails wiped immediately', () {
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);

      // Attempting to store while locked must have zero effect
      manager
        ..storeSandboxedToken('chaturbate', 'secret_token_123')
        ..storeVolatileThumbnail('thumb_1', Uint8List.fromList([1, 2, 3, 4]));
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);

      // Store while unlocked
      manager
        ..unlockForTesting()
        ..storeSandboxedToken('chaturbate', 'secret_token_123')
        ..storeVolatileThumbnail('thumb_1', Uint8List.fromList([1, 2, 3, 4]));
      expect(manager.getSandboxedToken('chaturbate'), equals('secret_token_123'));
      expect(manager.getVolatileThumbnail('thumb_1'), equals(Uint8List.fromList([1, 2, 3, 4])));

      // Lock should guarantee instant wipe and isUnlocked == false
      manager.lock();
      expect(manager.isUnlocked, isFalse);
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);
    });
  });
}
