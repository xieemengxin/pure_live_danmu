import 'barrage_logger.dart';

class Measure {
  const Measure._();

  /// Times [action] and logs its duration. Anything over 1 ms is logged at
  /// warning level so slow paths surface during development instead of being
  /// spotted on a device later.
  static T profile<T>(String label, T Function() action) {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      if (stopwatch.elapsedMicroseconds > 1000) {
        BarrageLogger.w(
          'Performance',
          '$label took ${stopwatch.elapsedMicroseconds} μs (${stopwatch.elapsedMilliseconds} ms)',
        );
      } else {
        BarrageLogger.d('Performance', '$label took ${stopwatch.elapsedMicroseconds} μs');
      }
    }
  }
}
