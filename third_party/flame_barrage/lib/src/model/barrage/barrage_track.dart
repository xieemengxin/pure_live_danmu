import 'package:flame_barrage/src/model/barrage/barrage_entry.dart';

class BarrageTrack {
  BarrageTrack({required this.index});

  final int index;

  /// Right edge of the youngest (rightmost) entry in this lane, in screen
  /// coordinates. Lane allocation uses it to decide whether the next message
  /// can enter without rear-ending the previous one.
  double lastRight = 0;

  /// Number of live entries currently assigned to this lane.
  int activeCount = 0;

  /// Set while a fixed (pinned) message occupies the lane; scroll messages
  /// must not enter a locked lane.
  bool locked = false;

  /// Monotonic engine time at which a fixed item releases this lane.
  int lockedUntil = 0;

  /// Engine time of the most recent launch into this lane.
  int lastLaunchTime = 0;

  BarrageEntry? lastEntry;

  /// Mean scroll speed of this lane's live entries, updated by the metrics
  /// system a few times per second. Feeds the lane-penalty heuristic.
  double avgSpeed = 0;

  /// Rough occupancy ratio of this lane relative to the screen width.
  double density = 0;
}
