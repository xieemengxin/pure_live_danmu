import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';

/// Runtime state of one motion effect on a single message.
///
/// Lifecycle: the data system creates this object at dispatch and fills in
/// the geometry snapshot (viewport, lane, danmaku bitmap size); the effect's
/// [BarrageMotionEffect.onSpawn] then places the entrance pose. Every logic
/// frame the motion system calls [BarrageMotionEffect.advance], the effect
/// writes the new position into [x]/[y] and the pose into
/// [alpha]/[rotation]/[scale], and the render system reads those values to
/// transform the danmaku bitmap, calling [BarrageMotionEffect.paint]
/// underneath it.
///
/// x/y live here rather than on the entry model so the effect layer never
/// depends back on it: these files import only dart:ui and the particle
/// system, keeping the dependency one-directional.
class BarrageFxState {
  /// The effect strategy driving this performance.
  BarrageMotionEffect? effect;

  /// Seconds since spawn, on the logic clock (scaled by the playback rate).
  double elapsed = 0;

  // ---- Per-frame output, consumed directly by the render system ----
  double x = 0;
  double y = 0;
  double alpha = 1;
  double rotation = 0;
  double scale = 1;

  // ---- Geometry snapshot frozen at dispatch time ----

  /// Logical size of the message's text bitmap.
  double entryWidth = 0;
  double entryHeight = 0;

  /// Top edge and height of the assigned lane.
  double laneTop = 0;
  double laneHeight = 0;

  double viewportWidth = 0;
  double viewportHeight = 0;

  /// Per-message random seed in 0..1, so every showing of the same effect
  /// differs in its details (step cadence, meteor angle, drift phase, ...).
  double seed = 0;

  /// Set by the effect to retire early (e.g. already flown out of the
  /// viewport); [BarrageMotionEffect.duration] remains the fallback expiry.
  bool done = false;

  /// Scratch memory for the effect: carries integration state across frames
  /// (current speed, spawn point, cruise duration, ...). Fixed at 12 slots so
  /// effects never own mutable objects that could be reused inconsistently.
  final List<double> mem = List<double>.filled(12, 0);

  /// Particle sink wired by the engine; effects spawn through [emit].
  BarrageFxParticleSystem? particles;

  /// Spawns one particle in world coordinates. Silently dropped when no
  /// particle system is wired (should not happen).
  void emit(BarrageFxParticle particle) => particles?.spawn(particle);
}

/// Motion strategy for effect danmaku.
///
/// Complements [BarrageEffectInterceptor], which changes what the text looks
/// like: this abstraction changes how a message enters, cruises and exits,
/// and can paint a mount — a horse, a plane, a dragon — underneath the text
/// via [paint].
///
/// Implementation contract:
/// * [duration] covers the whole performance (entrance + cruise + exit) in
///   seconds. The motion system recycles the entry once elapsed passes it; an
///   effect may also exit early by simply moving the entry out of the
///   viewport, with [duration] as the fallback.
/// * [advance] runs once per logic frame with dt already scaled by the
///   playback rate. Write [BarrageFxState.x]/y and the pose fields; never
///   hold a reference to the entry itself.
/// * [paint] receives a canvas already translated to the danmaku center with
///   the state's rotation/scale applied; draw relative to (0,0) as the
///   danmaku center — the text bitmap is painted on top.
abstract class BarrageMotionEffect {
  const BarrageMotionEffect();

  /// Total performance duration in seconds. The motion system recycles the
  /// entry and unlocks the lane at expiry.
  double get duration;

  /// Called once when the message lands on screen: set the spawn point
  /// [BarrageFxState.x]/y and the initial pose. The geometry snapshot
  /// (viewport, lane, bitmap size, seed) is ready, so path lengths and speed
  /// tiers can be precomputed into [BarrageFxState.mem] here.
  void onSpawn(BarrageFxState state);

  /// Advances one logic frame. dt is this frame's duration in seconds
  /// (playback rate and suspend guard already applied).
  void advance(BarrageFxState state, double dt);

  /// Draws the mount underneath the text bitmap. The canvas is translated
  /// to the danmaku center with rotation/scale applied; the mount multiplies
  /// its own alpha into its colors. No-op by default.
  void paint(ui.Canvas canvas, BarrageFxState state) {}
}

// =========================
// Easing helpers shared by motion effects
// =========================

double fxClamp01(double t) => t < 0 ? 0 : (t > 1 ? 1 : t);

double fxLerp(double a, double b, double t) => a + (b - a) * t;

double fxEaseOutCubic(double t) {
  final p = 1 - fxClamp01(t);
  return 1 - p * p * p;
}

double fxEaseInCubic(double t) {
  final p = fxClamp01(t);
  return p * p * p;
}

double fxEaseInOutSine(double t) {
  final p = fxClamp01(t);
  return -(math.cos(math.pi * p) - 1) / 2;
}

/// Overshoot-and-settle easing, for entrances that bounce into place.
double fxEaseOutBack(double t) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final p = fxClamp01(t);
  return 1 + c3 * (p - 1) * (p - 1) * (p - 1) + c1 * (p - 1) * (p - 1);
}

/// Multiplies an extra alpha into a color, used by mounts to respect the
/// entry's fade in/out: `fxA(color, state.alpha)`.
ui.Color fxA(ui.Color c, double alpha) => c.withValues(alpha: c.a * alpha);

/// Deterministic pseudo-random in 0..1 derived from the per-message seed, so
/// an effect's sub-details (dust size, sparkle rate) vary between showings
/// but stay stable within one.
double fxRand01(double seed, double salt) {
  final v = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}
