import 'dart:math' as math;

/// RFC 9562 UUIDv7 generator for Local-First entity identities.
///
/// Uses 48-bit UNIX epoch timestamp in milliseconds for time-based ordering,
/// followed by 74 bits of cryptographically secure random entropy.
String generateUuidV7() {
  final random = math.Random.secure();
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  final timeHigh = (nowMs >> 16) & 0xFFFFFFFF;
  final timeLow = nowMs & 0xFFFF;
  final verRandom = 0x7000 | random.nextInt(0x1000);
  final varRandom = 0x8000 | random.nextInt(0x4000);
  final rand1 = random.nextInt(0x10000);
  final rand2 = random.nextInt(0x10000);
  final rand3 = random.nextInt(0x10000);

  String hex(int val, int width) => val.toRadixString(16).padLeft(width, '0');

  return '${hex(timeHigh, 8)}-${hex(timeLow, 4)}-${hex(verRandom, 4)}-${hex(varRandom, 4)}-${hex(rand1, 4)}${hex(rand2, 4)}${hex(rand3, 4)}';
}

/// Hybrid Logical Clock (HLC) timestamp in microseconds.
///
/// Generates a monotonically non-decreasing timestamp in UTC.
int hybridLogicalClock([int lastHlc = 0]) {
  final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
  return nowUs > lastHlc ? nowUs : lastHlc + 1;
}
