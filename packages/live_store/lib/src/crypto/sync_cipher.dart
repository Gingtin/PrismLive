import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';

/// Cryptographic services for Local-First sync and secure backups.
///
/// Implements:
/// - PBKDF2-HMAC-SHA256 (RFC 2898 / RFC 8018) for key derivation from user passphrase.
/// - AES-256-GCM (NIST SP 800-38D / RFC 5116) authenticated encryption with 16-byte tag.
abstract final class SyncCipher {
  /// Magic bytes identifier for PrismLive encrypted sync payload ('PLSYNC1').
  static final Uint8List magicHeader = Uint8List.fromList(utf8.encode('PLSYNC1'));

  /// Derives a 32-byte (256-bit) AES key from [passphrase] and [salt] using PBKDF2-HMAC-SHA256.
  static Uint8List deriveKey(
    String passphrase,
    List<int> salt, {
    int iterations = 10000,
    int keyLength = 32,
  }) {
    if (salt.length < 8) {
      throw ArgumentError.value(salt.length, 'salt', 'Salt must be at least 8 bytes');
    }
    final passBytes = utf8.encode(passphrase);
    final hmac = Hmac(sha256, passBytes);
    final blocksNeeded = (keyLength + 31) ~/ 32;
    final derived = BytesBuilder();

    for (var blockIndex = 1; blockIndex <= blocksNeeded; blockIndex++) {
      // U1 = HMAC(pass, salt || INT_32_BE(blockIndex))
      final saltWithBlock = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt);
      ByteData.sublistView(saltWithBlock, salt.length).setUint32(0, blockIndex);

      var u = Uint8List.fromList(hmac.convert(saltWithBlock).bytes);
      final xorSum = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var i = 0; i < 32; i++) {
          xorSum[i] ^= u[i];
        }
      }
      derived.add(xorSum);
    }

    return Uint8List.sublistView(derived.takeBytes(), 0, keyLength);
  }

  /// Encrypts [plaintext] using AES-256-GCM.
  ///
  /// Returns a byte array containing:
  /// `[ciphertext (N bytes) | authentication tag (16 bytes)]`.
  static Uint8List encryptAesGcm(
    List<int> plaintext, {
    required List<int> key,
    required List<int> iv,
    List<int>? additionalData,
  }) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'AES-256-GCM requires a 32-byte key');
    }
    if (iv.length != 12) {
      throw ArgumentError.value(iv.length, 'iv', 'Standard GCM requires a 12-byte (96-bit) IV');
    }

    final aad = additionalData != null ? Uint8List.fromList(additionalData) : Uint8List(0);
    final pData = Uint8List.fromList(plaintext);

    // Hash subkey H = AES_K(0^128)
    final h = AesCbc.encryptBlock(Uint8List(16), key: key);

    // Initial counter J0 = IV || 00000001
    final j0 = Uint8List(16)
      ..setRange(0, 12, iv)
      ..[15] = 1;

    // GCTR encrypt plaintext starting at J0 + 1
    final ciphertext = _gctr(pData, key: key, initialCounter: _inc32(j0));

    // Calculate GHASH tag
    final s = _ghash(h, aad: aad, ciphertext: ciphertext);

    // T = MSB_128(S ^ GCTR(J0, 0^128)) = S ^ AES_K(J0)
    final tagMask = AesCbc.encryptBlock(j0, key: key);
    final tag = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      tag[i] = s[i] ^ tagMask[i];
    }

    return Uint8List(ciphertext.length + 16)
      ..setRange(0, ciphertext.length, ciphertext)
      ..setRange(ciphertext.length, ciphertext.length + 16, tag);
  }

  /// Decrypts [ciphertextAndTag] using AES-256-GCM.
  ///
  /// Expects `[ciphertext (N bytes) | authentication tag (16 bytes)]`.
  /// Throws [FormatException] if tag verification fails or length is invalid.
  static Uint8List decryptAesGcm(
    List<int> ciphertextAndTag, {
    required List<int> key,
    required List<int> iv,
    List<int>? additionalData,
  }) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'AES-256-GCM requires a 32-byte key');
    }
    if (iv.length != 12) {
      throw ArgumentError.value(iv.length, 'iv', 'Standard GCM requires a 12-byte (96-bit) IV');
    }
    if (ciphertextAndTag.length < 16) {
      throw const FormatException('Ciphertext is too short (must include 16-byte auth tag)');
    }

    final cipherLen = ciphertextAndTag.length - 16;
    final ciphertext = Uint8List.sublistView(
      Uint8List.fromList(ciphertextAndTag),
      0,
      cipherLen,
    );
    final expectedTag = Uint8List.sublistView(
      Uint8List.fromList(ciphertextAndTag),
      cipherLen,
      cipherLen + 16,
    );
    final aad = additionalData != null ? Uint8List.fromList(additionalData) : Uint8List(0);

    final h = AesCbc.encryptBlock(Uint8List(16), key: key);
    final j0 = Uint8List(16)
      ..setRange(0, 12, iv)
      ..[15] = 1;

    final s = _ghash(h, aad: aad, ciphertext: ciphertext);
    final tagMask = AesCbc.encryptBlock(j0, key: key);
    final calculatedTag = Uint8List(16);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      calculatedTag[i] = s[i] ^ tagMask[i];
      diff |= calculatedTag[i] ^ expectedTag[i];
    }

    if (diff != 0) {
      throw const FormatException('AES-GCM authentication failed: data tampered or invalid passphrase');
    }

    return _gctr(ciphertext, key: key, initialCounter: _inc32(j0));
  }

  /// Packs and encrypts a sync delta map into a self-contained secure byte packet.
  static Uint8List packEncryptedPayload(Map<String, Object?> delta, String passphrase) {
    final rand = math.Random.secure();
    final salt = Uint8List(16);
    final iv = Uint8List(12);
    for (var i = 0; i < 16; i++) {
      salt[i] = rand.nextInt(256);
    }
    for (var i = 0; i < 12; i++) {
      iv[i] = rand.nextInt(256);
    }

    final key = deriveKey(passphrase, salt);
    final jsonBytes = utf8.encode(jsonEncode(delta));
    final encrypted = encryptAesGcm(jsonBytes, key: key, iv: iv, additionalData: magicHeader);

    final builder = BytesBuilder()
      ..add(magicHeader) // 7 bytes
      ..add(salt) // 16 bytes
      ..add(iv) // 12 bytes
      ..add(encrypted); // ciphertext + 16 bytes tag

    return builder.takeBytes();
  }

  /// Unpacks and decrypts a sync packet into the decoded delta map.
  static Map<String, Object?> unpackEncryptedPayload(List<int> packetBytes, String passphrase) {
    if (packetBytes.length < magicHeader.length + 16 + 12 + 16) {
      throw const FormatException('Sync packet is truncated');
    }
    final bytes = Uint8List.fromList(packetBytes);
    for (var i = 0; i < magicHeader.length; i++) {
      if (bytes[i] != magicHeader[i]) {
        throw const FormatException('Invalid sync packet header');
      }
    }
    var offset = magicHeader.length;
    final salt = Uint8List.sublistView(bytes, offset, offset + 16);
    offset += 16;
    final iv = Uint8List.sublistView(bytes, offset, offset + 12);
    offset += 12;
    final encryptedWithTag = Uint8List.sublistView(bytes, offset);

    final key = deriveKey(passphrase, salt);
    final decryptedJsonBytes = decryptAesGcm(
      encryptedWithTag,
      key: key,
      iv: iv,
      additionalData: magicHeader,
    );
    final jsonStr = utf8.decode(decryptedJsonBytes);
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Sync packet payload is not a JSON object');
    }
    return decoded;
  }

  static Uint8List _inc32(Uint8List counter) {
    final copy = Uint8List.fromList(counter);
    for (var i = 15; i >= 12; i--) {
      copy[i] = (copy[i] + 1) & 0xff;
      if (copy[i] != 0) break;
    }
    return copy;
  }

  static Uint8List _gctr(Uint8List data, {required List<int> key, required Uint8List initialCounter}) {
    if (data.isEmpty) return Uint8List(0);
    final out = Uint8List(data.length);
    final counter = Uint8List.fromList(initialCounter);
    final numBlocks = (data.length + 15) ~/ 16;

    for (var b = 0; b < numBlocks; b++) {
      final keystream = AesCbc.encryptBlock(counter, key: key);
      final offset = b * 16;
      final len = math.min(16, data.length - offset);
      for (var i = 0; i < len; i++) {
        out[offset + i] = data[offset + i] ^ keystream[i];
      }
      // Increment counter lowest 32 bits
      for (var i = 15; i >= 12; i--) {
        counter[i] = (counter[i] + 1) & 0xff;
        if (counter[i] != 0) break;
      }
    }
    return out;
  }

  static Uint8List _ghash(Uint8List h, {required Uint8List aad, required Uint8List ciphertext}) {
    var y = Uint8List(16);

    void processBlocks(Uint8List data) {
      for (var offset = 0; offset < data.length; offset += 16) {
        final block = Uint8List(16);
        final len = math.min(16, data.length - offset);
        for (var i = 0; i < len; i++) {
          block[i] = data[offset + i];
        }
        for (var i = 0; i < 16; i++) {
          y[i] ^= block[i];
        }
        y = _gfMultiply(y, h);
      }
    }

    processBlocks(aad);
    processBlocks(ciphertext);

    // Final block: 64-bit len(A) in bits || 64-bit len(C) in bits
    final lenBlock = Uint8List(16);
    ByteData.sublistView(lenBlock)
      ..setUint64(0, aad.length * 8)
      ..setUint64(8, ciphertext.length * 8);

    for (var i = 0; i < 16; i++) {
      y[i] ^= lenBlock[i];
    }
    return _gfMultiply(y, h);
  }

  /// NIST SP 800-38D Algorithm 1: Multiplication in GF(2^128).
  static Uint8List _gfMultiply(Uint8List x, Uint8List y) {
    final z = Uint8List(16);
    final v = Uint8List.fromList(y);
    const rLsb = 0xe1;

    for (var i = 0; i < 128; i++) {
      final bit = (x[i >> 3] >> (7 - (i & 7))) & 1;
      if (bit != 0) {
        for (var j = 0; j < 16; j++) {
          z[j] ^= v[j];
        }
      }
      final lsb = v[15] & 1;
      var carry = 0;
      for (var j = 0; j < 16; j++) {
        final nextCarry = (v[j] & 1) << 7;
        v[j] = (v[j] >> 1) | carry;
        carry = nextCarry;
      }
      if (lsb != 0) {
        v[0] ^= rLsb;
      }
    }
    return z;
  }
}
