import 'package:flame/components.dart';

import '../model/barrage/barrage_entry.dart';
import '../model/barrage/barrage_item.dart';
import '../model/barrage/barrage_type.dart';
import '../core/barrage_context.dart';

/// Advances on-screen entries and recycles them the frame they leave.
///
/// Scrolling entries integrate against the logic clock; pinned entries turn
/// inactive at their expiry time. An inactive entry is removed from the list
/// and returned to the pool within the same frame using a tail swap — entry
/// order carries no meaning (lane allocation keeps items from overlapping),
/// so swapping beats a periodic sweep: no dead entries linger in the list
/// and render or hit-testing never walks them.
class BarrageMotionSystem extends Component {
  BarrageMotionSystem(this._ctx, {int priority = 200}) : super(priority: priority);

  final BarrageContext _ctx;

  @override
  void update(double dt) {
    final entries = _ctx.activeEntries;
    final now = _ctx.clock.nowPrecise();
    // The 200 ms cap only absorbs the gap left by a suspend/resume. Regular
    // frame jitter passes through untouched: position advances exactly with
    // real time, which is what keeps scroll velocity uniform regardless of
    // frame load.
    const maxDeltaMs = 200.0;
    int len = entries.length;
    int i = 0;
    while (i < len) {
      final entry = entries[i];
      final fx = entry.fx;
      if (entry.paused) {
        // Held by the host (e.g. an action sheet is open on it). Absorb the
        // elapsed time so resuming never jumps, and push the expiry forward
        // so pinned dwell does not run out while the user decides. Scroll
        // entries simply keep their position; effect choreography freezes.
        final deltaMs = (now - entry.lastUpdateTime).clamp(0.0, maxDeltaMs);
        entry.lastUpdateTime = now;
        entry.expireTime += deltaMs.round();
        i++;
        continue;
      }
      if (fx != null) {
        final deltaMs = (now - entry.lastUpdateTime).clamp(0.0, maxDeltaMs);
        entry.lastUpdateTime = now;
        final effect = fx.effect;
        if (effect != null) {
          final dt = deltaMs / 1000.0;
          fx.elapsed += dt;
          effect.advance(fx, dt);
          if (fx.done || fx.elapsed >= effect.duration) entry.active = false;
          // The effect owns the choreography: adopt its position every frame.
          entry.x = fx.x;
          entry.y = fx.y;
        } else {
          entry.active = false;
        }
      } else if (entry.item.type == BarrageType.scroll) {
        final deltaMs = (now - entry.lastUpdateTime).clamp(0.0, maxDeltaMs);
        entry.x -= entry.speed * deltaMs / 1000.0;
        entry.lastUpdateTime = now;
        if (entry.x + entry.width < 0) entry.active = false;
      } else if (now >= entry.expireTime) {
        entry.active = false;
      }

      if (!entry.active) {
        // Release an effect entry's exclusive lane the moment it exits: the
        // engine may pause right after (nothing else active), so the metrics
        // pass that normally clears lockedUntil would never run again.
        if (fx != null) _releaseLaneLock(entry);
        _release(entry);
        // Swap with the tail, shrink, and re-examine slot i: the moved
        // element has not been updated this frame yet.
        len--;
        entries[i] = entries[len];
        entries.length = len;
        continue;
      }
      i++;
    }
    _advanceParticles(now);
  }

  /// Takes every on-screen message matching [predicate] back off the screen
  /// (host-side retraction): releases its bitmap, returns the entry to the
  /// pool, drops it from the active list and clears any lane lock it held.
  /// Returns how many messages were taken back.
  ///
  /// Entries that are still waiting for a lane are dropped by
  /// [BarrageDataSystem.retractWhere]; callers that need both should go
  /// through [BarrageEngine.retractWhere].
  int retractWhere(bool Function(BarrageItem item) predicate) {
    final entries = _ctx.activeEntries;
    var removed = 0;
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (!predicate(entry.item)) continue;
      // Same order as the expiry path: drop the lane claim first, then the
      // bitmap/pool claim.
      if (entry.fx != null) _releaseLaneLock(entry);
      _release(entry);
      final last = entries.length - 1;
      entries[i] = entries[last];
      entries.length = last;
      removed++;
    }
    return removed;
  }

  /// Clears the lane lock a motion-effect show holds. Only touches the lock
  /// this entry set (lockedUntil matches its expiry); other kinds of locks
  /// are left to their owners.
  void _releaseLaneLock(BarrageEntry entry) {
    final tracks = _ctx.trackManager.tracks;
    final index = entry.track;
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    if (track.locked && track.lockedUntil <= entry.expireTime + 50) {
      track.locked = false;
      track.lockedUntil = 0;
    }
    if (identical(track.lastEntry, entry)) {
      track.lastEntry = null;
      track.lastRight = 0.0;
    }
  }

  /// Advances effect particles against the logic clock. Particles may outlive
  /// the entry that spawned them (smoke after a rocket exits), so this runs
  /// independently of the entry loop — with its own last-tick timestamp.
  void _advanceParticles(double now) {
    final particles = _ctx.fxParticles;
    if (!particles.hasAlive) {
      _lastParticleNow = 0;
      return;
    }
    if (_lastParticleNow == 0) {
      _lastParticleNow = now;
      return;
    }
    final dt = ((now - _lastParticleNow) / 1000.0).clamp(0.0, 0.2);
    _lastParticleNow = now;
    if (dt > 0) particles.advance(dt);
  }

  double _lastParticleNow = 0;

  /// Drops the entry's claim on its bitmap, then returns it to the pool. Safe
  /// to call twice: the second call finds nothing left to release.
  void _release(BarrageEntry entry) {
    final render = entry.render;
    if (render != null) {
      entry.render = null;
      _ctx.renderCache.release(render);
    }
    _ctx.aliveCount--;
    _ctx.pool.recycle(entry);
  }
}
