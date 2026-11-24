import 'dart:convert';
import 'dart:typed_data';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

void main() {
  group('SyncCipher Cryptographic Verification', () {
    test('PBKDF2 derives deterministic 256-bit keys', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key1 = SyncCipher.deriveKey('my-secret-password-123', salt, iterations: 1000);
      final key2 = SyncCipher.deriveKey('my-secret-password-123', salt, iterations: 1000);
      final key3 = SyncCipher.deriveKey('different-password', salt, iterations: 1000);

      expect(key1.length, 32);
      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
    });

    test('AES-256-GCM encryption and decryption roundtrip', () {
      final key = Uint8List(32)..fillRange(0, 32, 42);
      final iv = Uint8List(12)..fillRange(0, 12, 7);
      final plaintext = utf8.encode('Hello PureLive 4.x Local-First Sync!');
      final aad = utf8.encode('metadata-header');

      final encrypted = SyncCipher.encryptAesGcm(
        plaintext,
        key: key,
        iv: iv,
        additionalData: aad,
      );

      // Ciphertext length must be plaintext length + 16 bytes auth tag
      expect(encrypted.length, plaintext.length + 16);

      final decrypted = SyncCipher.decryptAesGcm(
        encrypted,
        key: key,
        iv: iv,
        additionalData: aad,
      );

      expect(utf8.decode(decrypted), 'Hello PureLive 4.x Local-First Sync!');
    });

    test('AES-256-GCM detects ciphertext tampering', () {
      final key = Uint8List(32)..fillRange(0, 32, 1);
      final iv = Uint8List(12)..fillRange(0, 12, 2);
      final plaintext = utf8.encode('Confidential live stream settings');

      final encrypted = SyncCipher.encryptAesGcm(plaintext, key: key, iv: iv);

      // Tamper 1 byte in ciphertext
      final tampered = Uint8List.fromList(encrypted);
      tampered[5] ^= 0x01;

      expect(
        () => SyncCipher.decryptAesGcm(tampered, key: key, iv: iv),
        throwsA(isA<FormatException>()),
      );
    });

    test('AES-256-GCM detects auth tag tampering', () {
      final key = Uint8List(32)..fillRange(0, 32, 1);
      final iv = Uint8List(12)..fillRange(0, 12, 2);
      final plaintext = utf8.encode('Confidential live stream settings');

      final encrypted = SyncCipher.encryptAesGcm(plaintext, key: key, iv: iv);

      // Tamper last byte (auth tag)
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => SyncCipher.decryptAesGcm(tampered, key: key, iv: iv),
        throwsA(isA<FormatException>()),
      );
    });

    test('AES-256-GCM detects additional data mismatch', () {
      final key = Uint8List(32)..fillRange(0, 32, 1);
      final iv = Uint8List(12)..fillRange(0, 12, 2);
      final plaintext = utf8.encode('Payload');

      final encrypted = SyncCipher.encryptAesGcm(
        plaintext,
        key: key,
        iv: iv,
        additionalData: utf8.encode('headerA'),
      );

      expect(
        () => SyncCipher.decryptAesGcm(
          encrypted,
          key: key,
          iv: iv,
          additionalData: utf8.encode('headerB'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('SyncPacket pack and unpack with passphrase roundtrip', () {
      const passphrase = 'UserMasterPassphrase!2026';
      final delta = <String, Object?>{
        'syncVersion': 4,
        'deviceId': 'device-alpha-pc',
        'follows': [
          {'identity': 'bilibili:12345', 'nick': 'Gamer'},
          {'identity': 'douyu:67890', 'nick': 'Pro'},
        ],
        'settings': [
          {'key': 'themeMode', 'value': 'dark'},
        ],
      };

      final packet = SyncCipher.packEncryptedPayload(delta, passphrase);
      expect(packet.length, greaterThan(SyncCipher.magicHeader.length + 28));

      final restored = SyncCipher.unpackEncryptedPayload(packet, passphrase);
      expect(restored['syncVersion'], 4);
      expect(restored['deviceId'], 'device-alpha-pc');
      expect((restored['follows']! as List).length, 2);
    });

    test('SyncPacket rejects wrong passphrase', () {
      const passphrase = 'CorrectPassphrase';
      final delta = <String, Object?>{'test': 'data'};

      final packet = SyncCipher.packEncryptedPayload(delta, passphrase);

      expect(
        () => SyncCipher.unpackEncryptedPayload(packet, 'WrongPassphrase'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
