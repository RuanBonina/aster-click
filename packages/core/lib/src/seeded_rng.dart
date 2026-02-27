library;

import 'contracts.dart';

/// Deterministic PRNG (LCG) for reproducible runs across platforms.
class SeededRng implements Rng {
  SeededRng(this.seed) : _state = seed & _mask;

  static const int _mask = 0x7fffffff;
  static const int _a = 1103515245;
  static const int _c = 12345;

  @override
  final int seed;
  int _state;

  int _nextRaw() {
    _state = (_a * _state + _c) & _mask;
    return _state;
  }

  @override
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max', 'must be > 0');
    }
    return _nextRaw() % max;
  }

  @override
  double nextDouble() {
    return _nextRaw() / _mask;
  }
}
