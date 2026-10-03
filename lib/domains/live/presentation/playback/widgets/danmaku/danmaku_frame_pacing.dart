/// Converts a danmaku logic-FPS cap into the `fps` handed to the barrage engine.
///
/// The engine throttles logic steps with `accumulated < 1 / fps`, and Flame
/// reports frame time in whole microseconds. A cap equal to the display rate
/// (or a divisor of it) therefore sits exactly on that boundary: at 60 Hz a
/// 16666 µs frame is shorter than 1/60 s, the step is skipped, and the next
/// frame moves twice as far. The layer still repaints every display frame, so
/// the held frame plus the double jump reads as stutter; with a 60 cap on a
/// 120 Hz display the steps land on every third frame instead of every second.
///
/// Lifting the cap a few percent moves the threshold off the boundary, so
/// steps land evenly on every k-th display frame. The engine clamps `fps` to
/// 240, which leaves caps above ~226 without headroom.
int danmakuEngineFps(int cap) => (cap * _boundaryHeadroom).ceil();

const double _boundaryHeadroom = 1.06;
