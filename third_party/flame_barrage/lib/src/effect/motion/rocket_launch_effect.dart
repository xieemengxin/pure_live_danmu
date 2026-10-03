import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Rocket launch: the message is the mission livery on the fuselage; the
/// rocket ignites at the bottom of the screen, accelerates off the top, and
/// trails billowing smoke and sparks the whole way.
///
/// * Ignition (0-0.55s) — the body shakes hard on the pad, the flame grows,
///   smoke pools at the base, the rocket lifts off slowly;
/// * Accelerating climb — linear speed gain, shake decaying with speed, full
///   flame, the smoke column left behind to drift upward;
/// * Exit — ends the moment the rocket clears the top; the particle system
///   finishes the smoke column naturally.
class RocketLaunchEffect extends BarrageMotionEffect {
  const RocketLaunchEffect({this.duration = 4.6});

  @override
  final double duration;

  // mem: 0=current speed 1=smoke/spark spawn metronome 2=flame phase
  static const int _kSpeed = 0;
  static const int _kEmitClock = 1;
  static const int _kFlamePhase = 2;

  static const double _accel = 90;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    state.mem[_kSpeed] = 40;
    state.x = state.viewportWidth * (0.15 + state.seed * 0.5) - w / 2;
    state.y = state.viewportHeight + 24;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;

    state.mem[_kSpeed] += _accel * dt;
    state.mem[_kFlamePhase] += dt * 26;
    state.y -= state.mem[_kSpeed] * dt;
    state.alpha = (t / 0.25).clamp(0.0, 1.0);

    // Ignition shake decays with speed: the body stabilizes after liftoff.
    final shake = (1 - fxClamp01(state.mem[_kSpeed] / 380)) * 2.4;
    state.x += math.sin(t * 47 + state.seed * 9) * shake * dt * 60 * 0.05;
    state.rotation = math.sin(t * 39 + state.seed * 5) * 0.012 * (shake + 0.3);

    _spawnExhaust(state, dt);
    if (state.y < -state.entryHeight * 2.2) {
      state.done = true;
    }
  }

  void _spawnExhaust(BarrageFxState state, double dt) {
    // Metronome: ~90 Hz cadence accumulated by dt; smoke and spark alternate.
    state.mem[_kEmitClock] += dt * 90;
    while (state.mem[_kEmitClock] >= 1) {
      state.mem[_kEmitClock] -= 1;
      final r = fxRand01(state.seed, state.elapsed * 91 + state.mem[_kEmitClock] * 13);
      final nozzleX = state.x + state.entryWidth / 2 + (r - 0.5) * 8;
      final nozzleY = state.y + state.entryHeight / 2 + _mountBottom(state);

      if (r < 0.72) {
        // Smoke: grey, expanding fast, drifting up slowly.
        state.emit(
          BarrageFxParticle(
            x: nozzleX + (r - 0.36) * 26,
            y: nozzleY + 4,
            vx: (r - 0.5) * 130,
            vy: 60 + r * 80,
            gravity: -46,
            drag: 0.94,
            maxLife: 1.3 + r * 0.9,
            startSize: 4.5,
            endSize: 15,
            color: const ui.Color(0x66B0BEC5),
          ),
        );
      } else {
        // Sparks: bright orange, short-lived, thrown by the flame.
        state.emit(
          BarrageFxParticle(
            x: nozzleX,
            y: nozzleY,
            vx: (r - 0.72) * 260,
            vy: 120 + r * 160,
            gravity: 60,
            drag: 0.9,
            maxLife: 0.3 + r * 0.25,
            startSize: 2.6,
            endSize: 0.3,
            color: const ui.Color(0xFFFFB74D),
          ),
        );
      }
    }
  }

  double _mountBottom(BarrageFxState state) {
    final bodyH = _bodyHeight(state);
    return state.entryHeight * 0.5 - 6 + bodyH + bodyH * 0.85;
  }

  double _bodyWidth(BarrageFxState state) =>
      (state.entryHeight * 0.85).clamp(22.0, 34.0);

  double _bodyHeight(BarrageFxState state) => _bodyWidth(state) * 2.7;

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final h = state.entryHeight;

    final bodyW = _bodyWidth(state);
    final bodyH = _bodyHeight(state);
    final top = h * 0.5 - bodyH * 0.42;
    final cx = 0.0; // fuselage centered under the text

    final whitePaint = ui.Paint()..color = fxA(const ui.Color(0xFFECEFF1), a);
    final redPaint = ui.Paint()..color = fxA(const ui.Color(0xFFE53935), a);
    final darkPaint = ui.Paint()..color = fxA(const ui.Color(0xFF546E7A), a);

    // Body.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(cx - bodyW / 2, top + bodyW * 0.6, bodyW, bodyH),
        ui.Radius.circular(bodyW * 0.24),
      ),
      whitePaint,
    );

    // Nose cone (red cone).
    final nose = ui.Path()
      ..moveTo(cx - bodyW / 2, top + bodyW * 0.72)
      ..lineTo(cx, top)
      ..lineTo(cx + bodyW / 2, top + bodyW * 0.72)
      ..close();
    canvas.drawPath(nose, redPaint);

    // Porthole.
    canvas.drawCircle(
      ui.Offset(cx, top + bodyW * 1.5),
      bodyW * 0.26,
      darkPaint,
    );
    canvas.drawCircle(
      ui.Offset(cx, top + bodyW * 1.5),
      bodyW * 0.18,
      ui.Paint()..color = fxA(const ui.Color(0xFF4FC3F7), a),
    );

    // Fins (red triangles on both sides).
    for (final dir in <double>[-1, 1]) {
      final fin = ui.Path()
        ..moveTo(cx + dir * bodyW * 0.5, top + bodyW * 0.6 + bodyH - bodyW * 0.9)
        ..lineTo(cx + dir * bodyW * 1.05, top + bodyW * 0.6 + bodyH)
        ..lineTo(cx + dir * bodyW * 0.5, top + bodyW * 0.6 + bodyH)
        ..close();
      canvas.drawPath(fin, redPaint);
    }

    // Flame: orange outer, yellow inner; length jitters with the flame phase
    // and intensifies after ignition.
    final power = fxClamp01(state.mem[_kSpeed] / 320);
    final flick = 0.72 + math.sin(state.mem[_kFlamePhase]) * 0.28;
    final flameLen = bodyH * (0.55 + power * 0.85) * flick;
    final baseY = top + bodyW * 0.6 + bodyH + bodyW * 0.35;
    final outer = ui.Path()
      ..moveTo(cx - bodyW * 0.30, baseY)
      ..lineTo(cx, baseY + flameLen)
      ..lineTo(cx + bodyW * 0.30, baseY)
      ..close();
    canvas.drawPath(outer, ui.Paint()..color = fxA(const ui.Color(0xFFFF6D00), a));
    final inner = ui.Path()
      ..moveTo(cx - bodyW * 0.15, baseY)
      ..lineTo(cx, baseY + flameLen * 0.55)
      ..lineTo(cx + bodyW * 0.15, baseY)
      ..close();
    canvas.drawPath(inner, ui.Paint()..color = fxA(const ui.Color(0xFFFFEA00), a));
  }
}
