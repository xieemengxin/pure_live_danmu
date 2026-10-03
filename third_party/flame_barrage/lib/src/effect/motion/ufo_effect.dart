import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// UFO cruise: a Canvas-drawn saucer descends slowly from above, its
/// tractor beam fading in as it wobbles across the barrage area before
/// suddenly flinging itself off upward, leaving a trail of blue-white warp dots.
///
/// * Entrance (0-1.4s) — descends from outside the viewport above the lane,
///   easeOutCubic decel with a 0.7-to-1 scale bounce, beam fading in;
/// * Cruise — slight tilt sway and hover bob, the tractor beam sweeping side
///   to side, rim lights cycling, occasional sparkles under the saucer;
/// * Exit (last 1.5s) — sudden acceleration toward the upper right, scaling
///   down to 0.55 and fading out over the final 0.45s, warp dots flung downward.
class UfoCruiseEffect extends BarrageMotionEffect {
  const UfoCruiseEffect({this.duration = 7.5});

  @override
  final double duration;

  // mem: 0=current speed 1=cruise base y 2=cruise speed
  static const int _kSpeed = 0;
  static const int _kBaseY = 1;
  static const int _kCruise = 2;

  static const double _entranceEnd = 1.4;
  static const double _exitStart = 6.0;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    final travel = state.viewportWidth + w + 160;
    state.mem[_kBaseY] = baseY;
    state.mem[_kCruise] = travel / duration;
    state.mem[_kSpeed] = state.mem[_kCruise];
    state.x = -w - 40;
    state.y = -state.entryHeight - 80;
    state.scale = 0.7;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;

    if (t < _entranceEnd) {
      final p = fxEaseOutCubic(t / _entranceEnd);
      state.y = fxLerp(-state.entryHeight - 80, state.mem[_kBaseY], p);
      state.scale = 0.7 + 0.3 * fxEaseOutBack(p);
      state.alpha = (t / 0.4).clamp(0.0, 1.0);
    } else if (t > _exitStart) {
      final p = fxClamp01((t - _exitStart) / (duration - _exitStart));
      // Ballistic exit: vertical velocity accumulates, overall scale shrinks,
      // and it fades out at the very end.
      state.mem[_kSpeed] += state.mem[_kCruise] * 1.4 * dt;
      state.y -= 560 * p * dt;
      state.scale = 1 - 0.45 * p;
      state.alpha = p > 0.7 ? 1 - (p - 0.7) / 0.3 : 1;
      _spawnWarpStreaks(state);
    } else {
      state.y = state.mem[_kBaseY] + math.sin(t * 2.6) * 4;
      state.alpha = 1;
      if (fxRand01(state.seed, t * 3.3) < 0.06) {
        _spawnRimSparkle(state);
      }
    }

    state.x += state.mem[_kSpeed] * dt;
    // Tilt sway + hover micro-bob.
    state.rotation = math.sin(t * 1.7 + state.seed * 6) * 0.06;
    if (t < _entranceEnd) state.rotation += math.sin(t * 9) * 0.03;
  }

  void _spawnRimSparkle(BarrageFxState state) {
    final r = fxRand01(state.seed, state.elapsed * 71);
    state.emit(
      BarrageFxParticle(
        x: state.x + state.entryWidth * (0.15 + r * 0.6),
        y: state.y + state.entryHeight * 1.05,
        vx: (r - 0.5) * 30,
        vy: 30 + r * 40,
        gravity: 40,
        drag: 0.95,
        maxLife: 0.7 + r * 0.4,
        startSize: 2.2,
        endSize: 0.3,
        color: const ui.Color(0xFFFFF59D),
      ),
    );
  }

  void _spawnWarpStreaks(BarrageFxState state) {
    final r = fxRand01(state.seed, state.elapsed * 83);
    state.emit(
      BarrageFxParticle(
        x: state.x + state.entryWidth * (0.2 + r * 0.6),
        y: state.y + state.entryHeight * 0.8,
        vx: (r - 0.5) * 60,
        vy: 220 + r * 160,
        maxLife: 0.4 + r * 0.25,
        startSize: 2.6,
        endSize: 0.4,
        color: const ui.Color(0xB3B3E5FC),
      ),
    );
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final h = state.entryHeight;

    final saucerW = (state.entryWidth * 0.22).clamp(66.0, 110.0);
    final saucerH = saucerW * 0.24;
    final cy = h * 0.52 + saucerH * 1.1;
    final cx = state.entryWidth * 0.30 - saucerW * 0.5;

    // Tractor beam: a conical gradient column under the saucer, sweeping with the tilt.
    final beamAlpha = a * (state.elapsed < _entranceEnd
        ? fxClamp01((state.elapsed - 0.5) / 0.9) * 0.4
        : state.elapsed > _exitStart ? 0.0 : 0.4);
    if (beamAlpha > 0.01) {
      final sway = math.sin(state.elapsed * 1.9 + state.seed * 4) * saucerW * 0.16;
      final beamTop = cy + saucerH * 0.35;
      final beamBottom = beamTop + saucerH * 4.2;
      final beam = ui.Path()
        ..moveTo(cx - saucerW * 0.10, beamTop)
        ..lineTo(cx + saucerW * 0.10, beamTop)
        ..lineTo(cx + saucerW * 0.42 + sway, beamBottom)
        ..lineTo(cx - saucerW * 0.42 + sway, beamBottom)
        ..close();
      final shader = ui.Gradient.linear(
        ui.Offset(cx, beamTop),
        ui.Offset(cx, beamBottom),
        [fxA(const ui.Color(0xFFFFF176), beamAlpha), fxA(const ui.Color(0xFFFFF176), 0)],
      );
      canvas.drawPath(beam, ui.Paint()..shader = shader);
    }

    // Saucer body: metallic grey ellipse + highlight.
    final bodyPaint = ui.Paint()..color = fxA(const ui.Color(0xFF90A4AE), a);
    canvas.drawOval(
      ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: saucerW, height: saucerH),
      bodyPaint,
    );
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(cx - saucerW * 0.08, cy - saucerH * 0.18),
        width: saucerW * 0.72,
        height: saucerH * 0.42,
      ),
      ui.Paint()..color = fxA(const ui.Color(0xFFCFD8DC), a),
    );

    // Glass dome.
    final dome = ui.Path()
      ..moveTo(cx - saucerW * 0.16, cy - saucerH * 0.25)
      ..quadraticBezierTo(cx, cy - saucerH * 1.9, cx + saucerW * 0.16, cy - saucerH * 0.25)
      ..close();
    canvas.drawPath(dome, ui.Paint()..color = fxA(const ui.Color(0x88B3E5FC), a));

    // Rim lights: four colors cycling around the rim.
    const palette = <ui.Color>[
      ui.Color(0xFF18FFFF),
      ui.Color(0xFFEA80FC),
      ui.Color(0xFFFFEA00),
      ui.Color(0xFF69F0AE),
    ];
    for (int i = 0; i < 6; i++) {
      final phase = (state.elapsed * 2.2 + i * 0.62) % palette.length;
      final c0 = palette[phase.floor()];
      final c1 = palette[(phase.floor() + 1) % palette.length];
      final mixed = ui.Color.lerp(c0, c1, phase - phase.floor()) ?? c0;
      final lx = cx - saucerW * 0.38 + i * saucerW * 0.152;
      final ly = cy + saucerH * 0.30 - math.sin(i / 5 * math.pi) * saucerH * 0.1;
      canvas.drawCircle(ui.Offset(lx, ly), 2.4, ui.Paint()..color = fxA(mixed, a));
    }
  }
}
