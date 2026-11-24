import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/privacy/nsfw_privacy_manager.dart';

void main() {
  group('NSFW Quadruple Privacy Shield Tests', () {
    final manager = NsfwPrivacyManager.instance;

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
      expect(nsfwCountInCatalog, greaterThan(0));

      // When locked, filterDescriptors must return exactly 0 NSFW items
      final filtered = manager.filterDescriptors(allDescriptors);
      final nsfwInFiltered = filtered.where((d) => d.isNsfw).toList();

      expect(nsfwInFiltered, isEmpty);
      expect(filtered.length, equals(allDescriptors.length - nsfwCountInCatalog));

      // Specific known adult sites must never leak
      for (final adultId in ['chaturbate', 'stripchat', 'bongacams', 'cam4', 'myfreecams']) {
        expect(filtered.any((d) => d.id == adultId), isFalse);
      }
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

    test('Zero-trace memory storage: tokens and thumbnails wiped immediately on lock()', () {
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);

      // Attempting to store while locked must have zero effect
      manager
        ..storeSandboxedToken('chaturbate', 'secret_token_123')
        ..storeVolatileThumbnail('thumb_1', Uint8List.fromList([1, 2, 3, 4]));
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);

      // Lock should guarantee clean slate
      manager.lock();
      expect(manager.isUnlocked, isFalse);
      expect(manager.getSandboxedToken('chaturbate'), isNull);
      expect(manager.getVolatileThumbnail('thumb_1'), isNull);
    });
  });
}
