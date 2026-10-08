/// Small deterministic PRNG (mulberry32).
///
/// `dart:math`'s `Random(seed)` is not guaranteed to produce the same sequence
/// on every platform/compiler, but Daily Challenges, friend duels and
/// server-side replay validation need the exact same rounds everywhere.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// Next 32-bit unsigned integer.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();

  /// Uniform double in [min, max).
  double range(double min, double max) => min + (max - min) * nextDouble();

  bool chance(double p) => nextDouble() < p;

  /// 32-bit multiply that stays exact even where ints are doubles (web).
  static int _imul(int a, int b) {
    final aHi = (a >> 16) & 0xFFFF, aLo = a & 0xFFFF;
    final bHi = (b >> 16) & 0xFFFF, bLo = b & 0xFFFF;
    final cross = ((aHi * bLo + aLo * bHi) & 0xFFFF) << 16;
    return (aLo * bLo + cross) & 0xFFFFFFFF;
  }
}
