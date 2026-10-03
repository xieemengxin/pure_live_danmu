/// How a message behaves once it reaches the screen.
enum BarrageType {
  /// Enters from the right edge and scrolls left until it leaves the screen.
  scroll,

  /// Pinned to a lane at the top for [BarrageConfig.fixedDuration].
  topFixed,

  /// Pinned to a lane at the bottom for [BarrageConfig.fixedDuration].
  bottomFixed,
}
