import 'package:flame/components.dart';

import '../model/barrage/barrage_entry.dart';
import '../core/barrage_context.dart';

/// Aggregates per-lane metrics at roughly 30 Hz for the lane allocator and
/// the speed strategy.
///
/// Read-only pass: it never mutates entries. For each lane it recomputes the
/// live count, mean scroll speed, rough occupancy and the right edge of the
/// youngest entry — the numbers lane allocation weighs when picking a lane.
/// Lanes pinned by a fixed message stay locked until that message expires.
class BarrageMetricsSystem extends Component {
  BarrageMetricsSystem(this._ctx, {int priority = 300}) : super(priority: priority);

  final BarrageContext _ctx;
  double _timer = 0.0;

  void clear() => _timer = 0.0;

  // Reused across calls so the steady-state path (track count unchanged)
  // does zero allocation. Reallocated only when the track count itself
  // changes (resize / config change), which is rare compared to the ~31
  // calls/sec this runs at. Allocating 3 fresh Lists every call was cheap
  // enough to be invisible on a phone's GC but shows up as periodic stutter
  // on weaker TV hardware.
  List<double> _trackSpeedBuf = const [];
  List<int> _trackCountBuf = const [];
  List<BarrageEntry?> _trackYoungestBuf = const [];

  @override
  void update(double dt) {
    _timer += dt;
    if (_timer < 0.032) return;
    _timer = 0.0;

    final tracks = _ctx.trackManager.tracks;
    final trackCount = tracks.length;
    if (trackCount == 0) return;

    if (_trackSpeedBuf.length != trackCount) {
      _trackSpeedBuf = List<double>.filled(trackCount, 0.0);
      _trackCountBuf = List<int>.filled(trackCount, 0);
      _trackYoungestBuf = List<BarrageEntry?>.filled(trackCount, null);
    } else {
      for (int t = 0; t < trackCount; t++) {
        _trackSpeedBuf[t] = 0.0;
        _trackCountBuf[t] = 0;
        _trackYoungestBuf[t] = null;
      }
    }

    final entries = _ctx.activeEntries;
    final entryLen = entries.length;
    for (int i = 0; i < entryLen; i++) {
      final entry = entries[i];
      final trackIndex = entry.track;
      if (trackIndex < 0 || trackIndex >= trackCount) continue;

      _trackSpeedBuf[trackIndex] += entry.speed;
      _trackCountBuf[trackIndex]++;
      final current = _trackYoungestBuf[trackIndex];
      if (current == null || entry.x > current.x) {
        _trackYoungestBuf[trackIndex] = entry;
      }
    }

    final screenWidth = _ctx.viewport.x;
    final now = _ctx.clock.now();
    for (int t = 0; t < trackCount; t++) {
      final track = tracks[t];
      final count = _trackCountBuf[t];
      track.activeCount = count;
      track.avgSpeed = count == 0 ? 0.0 : _trackSpeedBuf[t] / count;
      track.density = screenWidth > 0 ? (count * 150.0) / screenWidth : 0.0;

      final youngestEntry = _trackYoungestBuf[t];
      if (youngestEntry != null) {
        track.lastRight = youngestEntry.x + youngestEntry.width;
        track.lastEntry = youngestEntry;
      } else {
        if (!track.locked) {
          track.lastRight = 0.0;
          track.lastEntry = null;
        }
        if (track.locked && now >= track.lockedUntil) {
          track.locked = false;
          track.lockedUntil = 0;
          track.lastRight = 0.0;
          track.lastEntry = null;
        }
      }
    }
  }
}
