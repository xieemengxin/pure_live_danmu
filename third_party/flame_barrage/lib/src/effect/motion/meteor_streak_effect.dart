import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Meteor streak: the message becomes a meteor with a blazing tail, slicing
/// from the top right to the bottom left and burning out after crossing the
/// barrage area — barely three seconds, the fastest of the effect set.
///
/// * Entrance (0-0.2s) — pops in from 0.1 scale with a ring of white flash sparks;
/// * Cruise — fast diagonal flight, orange embers scattering behind, a breathing
///   heat glow behind the center, the tail pointing opposite the velocity;
/// * Burnout (last 0.4s) — the glow contracts, opacity falls to zero, and the
///   burnout point erupts in one last burst of sparks.
class MeteorStreakEffect extends BarrageMotionEffect {
  const MeteorStreakEffect({this.duration = 3.4});

  @override
  final double duration;

  // mem: 0=velocity vx 1=velocity vy 2=tail angle 3=burnout sparks fired
  static const int _kVx = 0;
  static const int _kVy = 1;
  static const int _kTailAngle = 2;
  static const int _kBurnt = 3;

  static const double _burnStart = 3.0;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    final startX = state.viewportWidth + w * 0.5;
    final startY = state.laneTop - state.entryHeight * 2.2 - state.seed * 50;
    final endX = -w * 1.5;
    final endY = state.laneTop + state.laneHeight + state.entryHeight * 3.2;

    final dx = endX - startX;
    final dy = endY - startY;
    final dist = math.sqrt(dx * dx + dy * dy);
    final v = dist / math.max(0.8, duration - 0.25);
    state.mem[_kVx] = dx / dist * v;
    state.mem[_kVy] = dy / dist * v;
    state.mem[_kTailAngle] = math.atan2(dy, dx);

    state.x = startX;
    state.y = startY;
    state.scale = 0.1;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;

    state.x += state.mem[_kVx] * dt;
    state.y += state.mem[_kVy] * dt;

    if (t < 0.2) {
      state.scale = 0.1 + 0.9 * fxEaseOutCubic(t / 0.2);
      if (t - dt <= 0.05) _spawnFlash(state);
    } else if (t > _burnStart) {
      final p = fxClamp01((t - _burnStart) / (duration - _burnStart));
      state.scale = 1 - 0.3 * p;
      state.alpha = 1 - p;
      if (state.mem[_kBurnt] == 0) {
        state.mem[_kBurnt] = 1;
        _spawnBurnout(state);
      }
    } else {
      state.scale = 1;
      state.alpha = 1;
      _spawnEmbers(state);
    }
  }

  void _spawnFlash(BarrageFxState state) {
    for (int i = 0; i < 8; i++) {
      final r = fxRand01(state.seed, 300 + i * 17);
      final angle = r * math.pi * 2;
      state.emit(
        BarrageFxParticle(
          x: state.x + state.entryWidth / 2,
          y: state.y + state.entryHeight / 2,
          vx: math.cos(angle) * (60 + r * 180),
          vy: math.sin(angle) * (60 + r * 180),
          drag: 0.88,
          maxLife: 0.3 + r * 0.2,
          startSize: 2.6,
          endSize: 0.3,
          color: const ui.Color(0xFFFFFFF8),
        ),
      );
    }
  }

  void _spawnEmbers(BarrageFxState state) {
    final w = state.entryWidth;
    final h = state.entryHeight;
    for (int i = 0; i < 2; i++) {
      final r = fxRand01(state.seed, state.elapsed * 67 + i * 29);
      state.emit(
        BarrageFxParticle(
          x: state.x + w * (0.25 + r * 0.5),
          y: state.y + h * (0.25 + fxRand01(state.seed, state.elapsed * 83 + i) * 0.5),
          vx: -state.mem[_kVx] * 0.12 + (r - 0.5) * 60,
          vy: -state.mem[_kVy] * 0.12 + (r - 0.5) * 60,
          gravity: 130,
          drag: 0.92,
          maxLife: 0.45 + r * 0.3,
          startSize: 2.4,
          endSize: 0.4,
          color: r > 0.5 ? const ui.Color(0xFFFFB74D) : const ui.Color(0xFFFF7043),
        ),
      );
    }
  }

  void _spawnBurnout(BarrageFxState state) {
    final cx = state.x + state.entryWidth / 2;
    final cy = state.y + state.entryHeight / 2;
    for (int i = 0; i < 12; i++) {
      final r = fxRand01(state.seed, 500 + i * 23);
      final angle = r * math.pi * 2;
      state.emit(
        BarrageFxParticle(
          x: cx,
          y: cy,
          vx: math.cos(angle) * (80 + r * 240),
          vy: math.sin(angle) * (80 + r * 240) + 40,
          gravity: 150,
          drag: 0.9,
          maxLife: 0.4 + r * 0.35,
          startSize: 3,
          endSize: 0.3,
          color: r > 0.4 ? const ui.Color(0xFFFFCC80) : const ui.Color(0xFFFFAB40),
        ),
      );
    }
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final h = state.entryHeight;


    // Heat glow: radial gradient, breathing over time.
    final pulse = 0.82 + math.sin(state.elapsed * 11) * 0.18;
    final glowR = h * 1.35 * pulse;
    final glowShader = ui.Gradient.radial(
      ui.Offset.zero,
      glowR,
      [
        fxA(const ui.Color(0xB3FFF59D), a),
        fxA(const ui.Color(0x66FF6D00), a),
        fxA(const ui.Color(0x00FF6D00), a),
      ],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawCircle(ui.Offset.zero, glowR, ui.Paint()..shader = glowShader);

    // Tail: conical gradient pointing opposite the velocity.
    final angle = state.mem[_kTailAngle];
    final tailLen = h * 3.6;
    final dirX = math.cos(angle);
    final dirY = math.sin(angle);
    final perpX = -dirY;
    final perpY = dirX;
    final tail = ui.Path()
      ..moveTo(perpX * h * 0.55, perpY * h * 0.55)
      ..lineTo(dirX * tailLen - perpX * h * 0.5, dirY * tailLen - perpY * h * 0.5)
      ..lineTo(dirX * tailLen + perpX * h * 0.5, dirY * tailLen + perpY * h * 0.5)
      ..lineTo(-perpX * h * 0.55, -perpY * h * 0.55)
      ..close();
    final tailShader = ui.Gradient.linear(
      ui.Offset.zero,
      ui.Offset(dirX * tailLen, dirY * tailLen),
      [
        fxA(const ui.Color(0xE6FFE082), a),
        fxA(const ui.Color(0x99FF6D00), a * 0.6),
        fxA(const ui.Color(0x00FF6D00), 0),
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawPath(tail, ui.Paint()..shader = tailShader);
  }
}
