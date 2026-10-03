import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Magic carpet: the message hovers above a Canvas-drawn Persian flying
/// carpet with rippling edges and gold tassels swaying at both ends. It flies
/// in diagonally from the lower left, crosses the barrage area, then accelerates
/// off the top right, trailing golden magic dust.
///
/// * Entrance (0-1.6s) — climbs along a diagonal from outside the lower-left
///   corner, nose dipping then leveling;
/// * Cruise — the edges ripple at about 3 Hz while the message rides the bob;
/// * Exit (last 1.5s) — nose up, accelerating toward the top right, ripple
///   intensifying, then fading out over the final 0.5s.
class MagicCarpetEffect extends BarrageMotionEffect {
  const MagicCarpetEffect({this.duration = 7.2});

  @override
  final double duration;

  // mem: 0=current speed 1=cruise base y 2=cruise speed 3=accumulated climb speed
  static const int _kSpeed = 0;
  static const int _kBaseY = 1;
  static const int _kCruise = 2;
  static const int _kClimb = 3;

  static const double _entranceEnd = 1.6;
  static const double _exitStart = 5.7;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    final travel = state.viewportWidth + w + 180;
    state.mem[_kBaseY] = baseY;
    state.mem[_kCruise] = travel / (duration + 0.3);
    state.mem[_kSpeed] = state.mem[_kCruise] * 0.75;
    state.mem[_kClimb] = 0;
    state.x = -w * 0.7;
    state.y = state.viewportHeight + 40;
    state.rotation = 0.16;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;

    double target = state.mem[_kCruise];
    if (t < _entranceEnd) {
      final p = fxEaseOutCubic(t / _entranceEnd);
      state.y = fxLerp(state.viewportHeight + 40, state.mem[_kBaseY], p);
      state.rotation = 0.16 * (1 - p);
      state.alpha = (t / 0.3).clamp(0.0, 1.0);
    } else if (t > _exitStart) {
      final p = fxClamp01((t - _exitStart) / (duration - _exitStart));
      target = state.mem[_kCruise] * 1.7;
      state.mem[_kClimb] += 300 * p * dt;
      state.y -= state.mem[_kClimb] * dt;
      state.rotation = -0.22 * p;
      state.alpha = p > 0.65 ? 1 - (p - 0.65) / 0.35 : 1;
    } else {
      state.y = state.mem[_kBaseY] + math.sin(t * 1.8) * 3;
      state.rotation = math.sin(t * 1.2) * 0.03;
      state.alpha = 1;
    }

    final newV = state.mem[_kSpeed] + (target - state.mem[_kSpeed]) * math.min(1.0, dt * 2.4);
    state.mem[_kSpeed] = newV;
    state.x += newV * dt;

    // Magic dust: sprinkled continuously from the carpet's tail.
    if (fxRand01(state.seed, t * 7.7) < 0.35) {
      final r = fxRand01(state.seed, t * 61);
      state.emit(
        BarrageFxParticle(
          x: state.x + state.entryWidth * (0.1 + r * 0.5),
          y: state.y + state.entryHeight * 0.95,
          vx: -20 + (r - 0.5) * 40,
          vy: 24 + r * 30,
          gravity: 60,
          drag: 0.95,
          maxLife: 0.7 + r * 0.5,
          startSize: 1.8,
          endSize: 0.3,
          color: r > 0.5 ? const ui.Color(0xFFFFE082) : const ui.Color(0xB3FFD54F),
        ),
      );
    }

    if (state.y < -state.entryHeight * 2 || state.x > state.viewportWidth + state.entryWidth + 60) {
      state.done = true;
    }
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final w = state.entryWidth;
    final h = state.entryHeight;

    final carpetW = math.max(96.0, w * 0.9);
    final carpetH = (h * 0.52).clamp(12.0, 22.0);
    final left = -carpetW / 2 + w * 0.08;
    final top = h * 0.42;
    final flutter = math.sin(state.elapsed * 3.0) * carpetH * 0.55;
    final flutter2 = math.sin(state.elapsed * 3.0 + 1.4) * carpetH * 0.5;

    // Carpet body: two bezier waves per edge, phase-offset so the surface twists.
    final carpet = ui.Path()
      ..moveTo(left, top)
      ..quadraticBezierTo(left + carpetW * 0.25, top - carpetH * 0.5 + flutter, left + carpetW * 0.5, top)
      ..quadraticBezierTo(left + carpetW * 0.75, top + carpetH * 0.5 + flutter2, left + carpetW, top + flutter2 * 0.4)
      ..lineTo(left + carpetW, top + carpetH)
      ..quadraticBezierTo(left + carpetW * 0.75, top + carpetH * 1.5 + flutter2, left + carpetW * 0.5, top + carpetH)
      ..quadraticBezierTo(left + carpetW * 0.25, top + carpetH * 0.5 + flutter, left, top + carpetH)
      ..close();
    canvas.drawPath(carpet, ui.Paint()..color = fxA(const ui.Color(0xFF6A1B9A), a));

    // Trim: one gold line along each edge.
    final trimPaint = ui.Paint()
      ..color = fxA(const ui.Color(0xFFFFD54F), a)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final trimTop = ui.Path()
      ..moveTo(left, top + carpetH * 0.18)
      ..quadraticBezierTo(left + carpetW * 0.5, top - carpetH * 0.35 + flutter, left + carpetW, top + carpetH * 0.18 + flutter2 * 0.4);
    canvas.drawPath(trimTop, trimPaint);
    final trimBottom = ui.Path()
      ..moveTo(left, top + carpetH * 0.82)
      ..quadraticBezierTo(left + carpetW * 0.5, top + carpetH * 1.35 + flutter, left + carpetW, top + carpetH * 0.82 + flutter2 * 0.4);
    canvas.drawPath(trimBottom, trimPaint);

    // Center pattern: three gold diamonds.
    final diamondPaint = ui.Paint()..color = fxA(const ui.Color(0xFFFFC107), a);
    for (int i = 0; i < 3; i++) {
      final dx = left + carpetW * (0.28 + i * 0.22);
      final dy = top + carpetH * 0.5 + (flutter + flutter2) * 0.25;
      final s = carpetH * 0.24;
      final diamond = ui.Path()
        ..moveTo(dx, dy - s)
        ..lineTo(dx + s * 1.4, dy)
        ..lineTo(dx, dy + s)
        ..lineTo(dx - s * 1.4, dy)
        ..close();
      canvas.drawPath(diamond, diamondPaint);
    }

    // Tassels: four per end, swaying with the ripple.
    final tasselPaint = ui.Paint()
      ..color = fxA(const ui.Color(0xFFFFD54F), a)
      ..strokeWidth = 1.4
      ..strokeCap = ui.StrokeCap.round;
    for (final dir in <double>[-1, 1]) {
      final edgeX = dir < 0 ? left : left + carpetW;
      for (int i = 0; i < 4; i++) {
        final ty = top + carpetH * (0.15 + i * 0.24);
        final sway = math.sin(state.elapsed * 3.4 + i * 0.7 + (dir < 0 ? 0 : 1.2)) * 3.5;
        canvas.drawLine(
          ui.Offset(edgeX, ty),
          ui.Offset(edgeX + dir * (5 + sway.abs()), ty + sway),
          tasselPaint,
        );
      }
    }
  }
}
