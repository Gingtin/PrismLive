import 'dart:convert';
import 'dart:typed_data';

import 'package:live_plugin_runtime/src/crypto/ed25519.dart';
import 'package:test/test.dart';

void main() {
  group('Ed25519 Sign & Verify', () {
    test('roundtrip sign and verify with arbitrary seed', () {
      final seed = Uint8List(32)..fillRange(0, 32, 42);
      final keyPair = Ed25519.generateKeyPairFromSeed(seed);
      final message = Uint8List.fromList(utf8.encode('PrismLive Plugin Test Payload 2026'));

      final signature = Ed25519.sign(message, keyPair.secretKey);
      expect(signature.length, equals(64));

      final isValid = Ed25519.verify(
        message: message,
        signature: signature,
        publicKey: keyPair.publicKey,
      );
      expect(isValid, isTrue);

      // Verify tampered message fails
      final tamperedMessage = Uint8List.fromList(utf8.encode('PrismLive Plugin Tampered Payload'));
      final isTamperedValid = Ed25519.verify(
        message: tamperedMessage,
        signature: signature,
        publicKey: keyPair.publicKey,
      );
      expect(isTamperedValid, isFalse);

      // Verify tampered signature fails
      final tamperedSig = Uint8List.fromList(signature);
      tamperedSig[0] ^= 0x01;
      final isTamperedSigValid = Ed25519.verify(
        message: message,
        signature: tamperedSig,
        publicKey: keyPair.publicKey,
      );
      expect(isTamperedSigValid, isFalse);
    });

    test('RFC 8032 Test Vector 1', () {
      // RFC 8032 Section 7.1 Test 1: empty message
      final seed = Ed25519.hexToBytes(
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
      );
      final keyPair = Ed25519.generateKeyPairFromSeed(seed);
      const expectedPub = 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
      expect(Ed25519.bytesToHex(keyPair.publicKey), equals(expectedPub));

      final emptyMessage = Uint8List(0);
      final sig = Ed25519.sign(emptyMessage, keyPair.secretKey);
      const expectedSig =
          'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
          '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';
      expect(Ed25519.bytesToHex(sig), equals(expectedSig));

      final valid = Ed25519.verify(
        message: emptyMessage,
        signature: sig,
        publicKey: keyPair.publicKey,
      );
      expect(valid, isTrue);
    });
  });
}
