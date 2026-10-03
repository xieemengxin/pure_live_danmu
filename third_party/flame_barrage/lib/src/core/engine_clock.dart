class EngineClock {
  double scale = 1.0;
  double _elapsedMs = 0.0;
  bool _isPaused = false;

  /// Logical time in whole milliseconds.
  ///
  /// Good enough for expiry deadlines and dispatch bookkeeping. Scroll motion
  /// must use [nowPrecise] instead — see its documentation for why.
  int now() => _elapsedMs.round();

  /// Logical time in milliseconds with sub-millisecond precision.
  ///
  /// Integer millisecond rounding shifts each frame's position delta by up to
  /// ±0.5 ms. At 144 steps per second a frame advances only ~6.9 ms, so that
  /// rounding alone perturbs the per-frame delta by up to ±7% — visible as
  /// uneven motion on high refresh rate panels. Position integration therefore
  /// always reads this method.
  double nowPrecise() => _elapsedMs;

  void tick(double dt) {
    if (!_isPaused) _elapsedMs += dt * 1000.0 * scale;
  }

  void pause() {
    if (_isPaused) return;
    _isPaused = true;
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
  }

  void reset() {
    _elapsedMs = 0.0;
    _isPaused = false;
  }

  bool get isPaused => _isPaused;
}
