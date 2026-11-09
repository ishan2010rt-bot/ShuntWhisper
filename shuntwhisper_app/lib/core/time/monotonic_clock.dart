import 'dart:io';

/// Abstraction for nanosecond monotonic clock.
/// Adheres to Invariant I2: Monotonic time only for physical elapsed intervals.
abstract class MonotonicClock {
  /// Returns the current monotonic time in nanoseconds.
  int nowNanos();

  /// Returns current elapsed seconds since t0 in nanoseconds.
  double elapsedSecondsSince(int t0Nanos) {
    return (nowNanos() - t0Nanos) / 1e9;
  }
}

class SystemMonotonicClock implements MonotonicClock {
  const SystemMonotonicClock();

  @override
  int nowNanos() {
    // In Dart standard library, Stopwatch uses high-resolution monotonic timer
    return Stopwatch().elapsedTicks * (1000000000 ~/ Stopwatch().frequency);
  }
}

class FakeMonotonicClock implements MonotonicClock {
  int _currentNanos;

  FakeMonotonicClock([this._currentNanos = 0]);

  void advance(Duration duration) {
    _currentNanos += duration.inMicroseconds * 1000;
  }

  void advanceSeconds(double seconds) {
    _currentNanos += (seconds * 1e9).toInt();
  }

  void setNanos(int nanos) {
    _currentNanos = nanos;
  }

  @override
  int nowNanos() => _currentNanos;
}
