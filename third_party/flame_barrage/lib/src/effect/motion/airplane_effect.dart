import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Jet airliner: the message rides like an airline livery slogan on a
/// Canvas-drawn jet that climbs in from the lower left, cruises across the
/// barrage area, then pulls up and exits at the top right trailing a white
/// contrail the whole way.
///
/// * Entrance (0-1.3s) — climbs into place from 55 px below the lane at
///   0.85 scale, nose pitching up then leveling;
/// * Cruise — light turbulence bobbing, a continuous contrail from the tail
///   (white particles sinking and dissipating), red beacon blinking;
/// * Exit (last 1.6s) — pitch up, accelerate, climb; the trail thickens as
///   the jet exits at the top right.
class AirplaneEffect extends BarrageMotionEffect {
  const AirplaneEffect({this.duration = 7.0});

  @override
  final double duration;

  // mem: 0=current speed 1=cruise base y 2=cruise speed 3=climb y offset
  static const int _kSpeed = 0;
  static const int _kBaseY = 1;
  static const int _kCruise = 2;
  static const int _kClimb = 3;

  static const double _entranceEnd = 1.3;
  static const double _exitStart = 5.4;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    final travel = state.viewportWidth + w + 200;
    state.mem[_kBaseY] = baseY;
    // Time budget incl. the slow climb-in and the fast climb-out.
    state.mem[_kCruise] = travel / (duration + 0.5);
    state.mem[_kSpeed] = state.mem[_kCruise] * 0.7;
    state.mem[_kClimb] = 0;
    state.x = -w - 60;
    state.y = baseY + 55;
    state.scale = 0.85;
    state.rotation = -0.16;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;
    final cruise = state.mem[_kCruise];

    double target = cruise;
    double rotation = 0;

    if (t < _entranceEnd) {
      final p = fxEaseOutCubic(t / _entranceEnd);
      state.y = fxLerp(state.mem[_kBaseY] + 55, state.mem[_kBaseY], p);
      state.mem[_kClimb] = 0;
      rotation = -0.16 * (1 - p);
      state.scale = 0.85 + 0.15 * p;
      state.alpha = (t / 0.35).clamp(0.0, 1.0);
    } else if (t > _exitStart) {
      final p = fxClamp01((t - _exitStart) / (duration - _exitStart));
      target = cruise * 1.9;
      rotation = -0.34 * p;
      // Pull-up climb: displacement integrated from acceleration, ever steeper.
      state.mem[_kClimb] += 260 * p * dt;
      state.y -= state.mem[_kClimb] * dt;
      _spawnContrail(state, dense: true);
    } else {
      state.alpha = 1;
      _spawnContrail(state, dense: false);
    }

    final newV = state.mem[_kSpeed] + (target - state.mem[_kSpeed]) * math.min(1.0, dt * 2.5);
    state.mem[_kSpeed] = newV;
    state.x += newV * dt;
    state.rotation = rotation;

    if (t >= _entranceEnd && t <= _exitStart) {
      state.y = state.mem[_kBaseY] + math.sin(t * 1.3) * 2.5;
    }
    if (state.y < -state.entryHeight * 2 || state.x > state.viewportWidth + state.entryWidth + 60) {
      state.done = true;
    }
  }

  void _spawnContrail(BarrageFxState state, {required bool dense}) {
    final count = dense ? 2 : 1;
    final r = fxRand01(state.seed, state.elapsed * 31);
    for (int i = 0; i < count; i++) {
      state.emit(
        BarrageFxParticle(
          x: state.x + state.entryWidth * 0.02,
          y: state.y + state.entryHeight * (0.55 + fxRand01(state.seed, state.elapsed * 47 + i) * 0.25),
          vx: -70 - r * 40,
          vy: 8 + r * 10,
          drag: 0.985,
          maxLife: 1.1 + r * 0.6,
          startSize: dense ? 3.0 : 2.2,
          endSize: 6.5,
          color: const ui.Color(0x59FFFFFF),
        ),
      );
    }
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final h = state.entryHeight;
    final w = state.entryWidth;

    final bodyLen = (w * 0.24).clamp(64.0, 104.0);
    final bodyH = (h * 0.62).clamp(14.0, 22.0);
    final cy = h * 0.52 + bodyH * 0.55;
    final cx = w * 0.30 - bodyLen * 0.5;

    final bodyPaint = ui.Paint()..color = fxA(const ui.Color(0xFFECEFF1), a);
    final darkPaint = ui.Paint()..color = fxA(const ui.Color(0xFF455A64), a);
    final accentPaint = ui.Paint()..color = fxA(const ui.Color(0xFFE53935), a);

    // Wings: swept triangles extending back and down from mid-fuselage.
    final wing = ui.Path()
      ..moveTo(cx + bodyLen * 0.12, cy + bodyH * 0.1)
      ..lineTo(cx - bodyLen * 0.10, cy + bodyH * 1.35)
      ..lineTo(cx + bodyLen * 0.02, cy + bodyH * 1.35)
      ..lineTo(cx + bodyLen * 0.24, cy + bodyH * 0.1)
      ..close();
    canvas.drawPath(wing, darkPaint);

    // Tail: vertical stabilizer.
    final fin = ui.Path()
      ..moveTo(cx - bodyLen * 0.42, cy - bodyH * 0.1)
      ..lineTo(cx - bodyLen * 0.52, cy - bodyH * 1.25)
      ..lineTo(cx - bodyLen * 0.36, cy - bodyH * 1.2)
      ..lineTo(cx - bodyLen * 0.26, cy - bodyH * 0.1)
      ..close();
    canvas.drawPath(fin, accentPaint);

    // Fuselage: rounded bar + nose fairing.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(cx - bodyLen * 0.5, cy - bodyH * 0.5, bodyLen * 0.88, bodyH),
        ui.Radius.circular(bodyH * 0.5),
      ),
      bodyPaint,
    );
    canvas.save();
    canvas.translate(cx + bodyLen * 0.44, cy);
    canvas.scale(1.0, 0.5);
    canvas.drawCircle(ui.Offset.zero, bodyH * 0.5, bodyPaint);
    canvas.restore();

    // Cockpit windshield.
    canvas.drawArc(
      ui.Rect.fromCenter(center: ui.Offset(cx + bodyLen * 0.36, cy - bodyH * 0.16), width: bodyH * 0.6, height: bodyH * 0.5),
      math.pi + 0.35,
      0.9,
      false,
      darkPaint,
    );

    // Window band.
    final windowPaint = ui.Paint()..color = fxA(const ui.Color(0xFF78909C), a);
    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(
        ui.Offset(cx - bodyLen * 0.28 + i * bodyLen * 0.105, cy - bodyH * 0.08),
        bodyH * 0.09,
        windowPaint,
      );
    }

    // Tail beacon: red strobe.
    final blink = (math.sin(state.elapsed * 5) + 1) / 2;
    canvas.drawCircle(
      ui.Offset(cx - bodyLen * 0.44, cy - bodyH * 0.95),
      2.2,
      ui.Paint()..color = fxA(const ui.Color(0xFFFF1744), 0.25 + 0.75 * blink),
    );
  }
}
