import 'dart:math';

final Random _rng = Random();

/// Unique-enough id for in-memory tasks and config profiles: the current
/// microsecond timestamp plus 32 bits of randomness. Not crypto-grade, just
/// collision-resistant in practice.
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32)}';
