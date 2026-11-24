/// RFC 8032 compliant Ed25519 signature verification and key handling in pure Dart.
library;

import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Constant prime $p = 2^{255} - 19$.
final BigInt _p = (BigInt.one << 255) - BigInt.from(19);

/// Curve constant $d = -121665 / 121666 \pmod p$.
final BigInt _d = (-BigInt.from(121665) * _modInverse(BigInt.from(121666), _p)) % _p;

/// Group order $\ell = 2^{252} + 27742317777372353535851937790883648493$.
final BigInt _l = (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');

/// Constant $\sqrt{-1} \pmod p$.
final BigInt _i = _modPow(BigInt.from(2), (_p - BigInt.one) ~/ BigInt.from(4), _p);

/// Base point B(x, y).
final BigInt _by = (BigInt.from(4) * _modInverse(BigInt.from(5), _p)) % _p;
final BigInt _bx = _recoverX(_by, 0);

/// Modular exponentiation: base^exp % mod.
BigInt _modPow(BigInt base, BigInt exponent, BigInt modulus) {
  return base.modPow(exponent, modulus);
}

/// Modular inverse using Fermat's Little Theorem: a^(p-2) % p.
BigInt _modInverse(BigInt a, BigInt modulus) {
  return a.modPow(modulus - BigInt.two, modulus);
}

/// Recovers x coordinate from y coordinate and parity bit.
BigInt _recoverX(BigInt y, int sign) {
  if (y >= _p) throw ArgumentError('y coordinate out of range');
  final y2 = (y * y) % _p;
  final u = (y2 - BigInt.one) % _p;
  final v = (_d * y2 + BigInt.one) % _p;
  final xx = (u * _modInverse(v, _p)) % _p;
  var x = _modPow(xx, (_p + BigInt.from(3)) ~/ BigInt.from(8), _p);

  if (((x * x - xx) % _p) != BigInt.zero) {
    x = (x * _i) % _p;
  }
  if (((x * x - xx) % _p) != BigInt.zero) {
    throw ArgumentError('Invalid point coordinates');
  }
  if ((x.isOdd ? 1 : 0) != sign) {
    x = (_p - x) % _p;
  }
  return x;
}

/// Extended twisted Edwards curve point: (X : Y : Z : T) where x = X/Z, y = Y/Z, xy = T/Z.
class _Point {
  const new(this.x, this.y, this.z, this.t);

  /// Decodes 32-byte representation into point.
  factory decode(Uint8List bytes) {
    if (bytes.length != 32) throw ArgumentError('Expected 32 bytes for point');
    final sign = (bytes[31] & 0x80) != 0 ? 1 : 0;
    final copy = Uint8List.fromList(bytes);
    copy[31] &= 0x7F;
    final y = _decodeLittleEndian(copy);
    final x = _recoverX(y, sign);
    return _Point(x, y, BigInt.one, (x * y) % _p);
  }

  static final _Point identity = _Point(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);
  static final _Point base = _Point(_bx, _by, BigInt.one, (_bx * _by) % _p);

  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;

  /// Point addition.
  _Point operator +(_Point other) {
    final a = ((y - x) * (other.y - other.x)) % _p;
    final b = ((y + x) * (other.y + other.x)) % _p;
    final c = (t * BigInt.two * _d * other.t) % _p;
    final d = (z * BigInt.two * other.z) % _p;
    final e = (b - a) % _p;
    final f = (d - c) % _p;
    final g = (d + c) % _p;
    final h = (b + a) % _p;

    return _Point((e * f) % _p, (h * g) % _p, (g * f) % _p, (e * h) % _p);
  }

  /// Scalar multiplication.
  _Point operator *(BigInt scalar) {
    var result = identity;
    var addend = this;
    var k = scalar;
    while (k > BigInt.zero) {
      if (k.isOdd) {
        result = result + addend;
      }
      addend = addend + addend;
      k >>= 1;
    }
    return result;
  }

  /// Encodes point to 32 bytes.
  Uint8List encode() {
    final zInv = _modInverse(z, _p);
    final normX = (x * zInv) % _p;
    final normY = (y * zInv) % _p;
    final bytes = _encodeLittleEndian(normY, 32);
    if (normX.isOdd) {
      bytes[31] |= 0x80;
    }
    return bytes;
  }
}

BigInt _decodeLittleEndian(Uint8List bytes) {
  var result = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

Uint8List _encodeLittleEndian(BigInt value, int length) {
  final bytes = Uint8List(length);
  var v = value;
  for (var i = 0; i < length; i++) {
    bytes[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  return bytes;
}

/// Official and community Ed25519 signature operations for live plugins.
abstract final class Ed25519 {
  /// Well-known official PrismLive release public key for verified plugins.
  static const String officialPublicKeyHex =
      '5cc7dadd038a3dbcb265d860f5e83d01652dfe2c0ceed234f05a8d2d8f9e6efb';

  /// Generates a key pair (seed 32 bytes, secretKey 64 bytes, publicKey 32 bytes).
  static ({Uint8List secretKey, Uint8List publicKey}) generateKeyPairFromSeed(Uint8List seed) {
    if (seed.length != 32) throw ArgumentError('Seed must be 32 bytes');
    final digest = crypto.sha512.convert(seed).bytes;
    final h = Uint8List.fromList(digest);
    h[0] &= 248;
    h[31] &= 127;
    h[31] |= 64;

    final a = _decodeLittleEndian(Uint8List.sublistView(h, 0, 32));
    final pubPoint = _Point.base * a;
    final pubBytes = pubPoint.encode();

    final secretKey = Uint8List(64)
      ..setRange(0, 32, seed)
      ..setRange(32, 64, pubBytes);

    return (secretKey: secretKey, publicKey: pubBytes);
  }

  /// Signs [message] using 64-byte [secretKey].
  static Uint8List sign(Uint8List message, Uint8List secretKey) {
    if (secretKey.length != 64) throw ArgumentError('Secret key must be 64 bytes');
    final seed = Uint8List.sublistView(secretKey, 0, 32);
    final pubBytes = Uint8List.sublistView(secretKey, 32, 64);

    final digest1 = crypto.sha512.convert(seed).bytes;
    final h = Uint8List.fromList(digest1);
    h[0] &= 248;
    h[31] &= 127;
    h[31] |= 64;
    final a = _decodeLittleEndian(Uint8List.sublistView(h, 0, 32));

    final rBytes = crypto.sha512
        .convert([...Uint8List.sublistView(h, 32, 64), ...message])
        .bytes;
    final r = _decodeLittleEndian(Uint8List.fromList(rBytes)) % _l;
    final rPoint = _Point.base * r;
    final encodedR = rPoint.encode();

    final kBytes = crypto.sha512
        .convert([...encodedR, ...pubBytes, ...message])
        .bytes;
    final k = _decodeLittleEndian(Uint8List.fromList(kBytes)) % _l;
    final s = (r + k * a) % _l;
    final encodedS = _encodeLittleEndian(s, 32);

    final signature = Uint8List(64)
      ..setRange(0, 32, encodedR)
      ..setRange(32, 64, encodedS);
    return signature;
  }

  /// Verifies whether [signature] is valid for [message] against [publicKey].
  static bool verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) {
    if (signature.length != 64) return false;
    if (publicKey.length != 32) return false;

    try {
      final rBytes = Uint8List.sublistView(signature, 0, 32);
      final sBytes = Uint8List.sublistView(signature, 32, 64);
      final s = _decodeLittleEndian(sBytes);
      if (s >= _l) return false;

      final aPoint = _Point.decode(publicKey);
      final kBytes = crypto.sha512
          .convert([...rBytes, ...publicKey, ...message])
          .bytes;
      final k = _decodeLittleEndian(Uint8List.fromList(kBytes)) % _l;

      // Check: S * B == R + k * A
      final sb = _Point.base * s;
      final ka = aPoint * k;
      final rPoint = _Point.decode(rBytes);
      final rPlusKa = rPoint + ka;

      return sb.encode().elementsEqual(rPlusKa.encode());
    } on Object {
      return false;
    }
  }

  /// Helper to convert hex string to bytes.
  static Uint8List hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Helper to convert bytes to hex string.
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

extension on Uint8List {
  bool elementsEqual(Uint8List other) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}
