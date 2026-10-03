import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Horse-riding entrance: a galloping charger storms in from the left edge
/// with the message floating above its back like a rider's banner.
///
/// Three-phase choreography:
/// * Entrance (0-1.1s) — bounces in with an easeOutBack scale-up, head
///   tossing upward, dust bursting at every hoof-fall;
/// * Cruise — running with a gait-driven bob, four legs swinging in a trot
///   phase, mane and tail streaming with speed, dust trailing the hooves;
/// * Sprint exit (last 1.3s) — 2.6x speed with a forward lean, speed
///   afterimages trailing behind.
///
/// The mount is a chestnut horse drawn entirely with Canvas primitives; no
/// image assets.
class HorseRidingEffect extends BarrageMotionEffect {
  const HorseRidingEffect({this.duration = 7.5});

  /// Total performance duration in seconds: entrance + cruise + sprint.
  @override
  final double duration;

  // mem slots: 0=current speed 1=gait phase (cycles) 2=cruise base y 3=gait rate (Hz)
  // 4=half-cycle remainder of the last hoof-fall 5=cruise speed v
  static const int _kSpeed = 0;
  static const int _kGallopPhase = 1;
  static const int _kBaseY = 2;
  static const int _kGallopHz = 3;
  static const int _kLastStride = 4;
  static const int _kCruiseSpeed = 5;

  static const double _entranceEnd = 1.1;

  @override
  void onSpawn(BarrageFxState state) {
    final w = state.entryWidth;
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    final travel = state.viewportWidth + w + 190;
    state.mem[_kBaseY] = baseY;
    // Cruise speed = total travel / a time budget that includes the slower
    // entrance and the faster dash; the rough integral works out to
    // duration+0.95, so the on-screen dash happens inside the viewport.
    state.mem[_kCruiseSpeed] = travel / (duration + 0.95);
    state.mem[_kSpeed] = state.mem[_kCruiseSpeed] * 0.55;
    state.mem[_kGallopHz] = 2.1 + fxRand01(state.seed, 1) * 0.7;
    state.x = -w - 90;
    state.y = baseY;
    state.scale = 0.5;
    state.alpha = 0;
    state.rotation = -0.22;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;
    final v = state.mem[_kSpeed];
    final cruise = state.mem[_kCruiseSpeed];

    double target = cruise;
    double scale = 1;
    double rotation = 0;
    final tau = math.pi * 2;

    if (t < _entranceEnd) {
      final p = t / _entranceEnd;
      target = cruise * 0.6;
      scale = 0.5 + 0.5 * fxEaseOutBack(p);
      state.alpha = (t / 0.3).clamp(0.0, 1.0);
      rotation = -0.22 * (1 - fxEaseOutCubic(p));
    } else if (t > duration - 1.3) {
      // Sprint exit: 2.6x speed, forward lean, slight zoom, speed afterimages.
      final p = fxClamp01((t - (duration - 1.3)) / 1.3);
      target = cruise * 2.6;
      scale = 1 + 0.06 * p;
      rotation = 0.10 * p;
      if (state.alpha > 0.999) {
        _spawnStreaks(state, v);
      }
    } else {
      state.alpha = 1;
    }

    // Speed eases toward the target so phase transitions never jump.
    final newV = v + (target - v) * math.min(1.0, dt * 3.0);
    state.mem[_kSpeed] = newV;
    state.x += newV * dt;
    state.scale = scale;
    state.rotation = rotation + math.sin(state.mem[_kGallopPhase] * tau + 0.9) * 0.035;

    state.mem[_kGallopPhase] += dt * state.mem[_kGallopHz];
    state.y = state.mem[_kBaseY] + math.sin(state.mem[_kGallopPhase] * tau) * 3.0;

    if (t > 0.35 && t < duration - 0.15) {
      _spawnHoofDust(state);
    }
    if (t >= _entranceEnd && t - dt < _entranceEnd) {
      _spawnLandingBurst(state);
    }
    if (state.x > state.viewportWidth + state.entryWidth + 40) {
      state.done = true;
    }
  }

  // ---- Particles ----

  void _spawnHoofDust(BarrageFxState state) {
    // One hoof-fall every half gait cycle (front/rear alternating), spawned at
    // the world position of the horse's rear.
    final half = (state.mem[_kGallopPhase] % 0.5);
    final prev = state.mem[_kLastStride];
    state.mem[_kLastStride] = half;
    if (half >= prev) return;

    final w = state.entryWidth;
    final h = state.entryHeight;
    final hoofX = state.x + w * 0.5 + w * 0.42 - _bodyLength(state) * 0.77 - fxRand01(state.seed, half * 37) * 24;
    final hoofY = state.y + h / 2 + _mountBottom(state) * 0.92;
    for (int i = 0; i < 2; i++) {
      final r = fxRand01(state.seed, half * 53 + i * 7);
      state.emit(
        BarrageFxParticle(
          x: hoofX + (r - 0.5) * 10,
          y: hoofY,
          vx: -(50 + r * 90) - state.mem[_kSpeed] * 0.22,
          vy: -(15 + fxRand01(state.seed, half * 91 + i) * 55),
          gravity: 240,
          drag: 0.88,
          maxLife: 0.45 + r * 0.35,
          startSize: 2,
          endSize: 6.5,
          color: const ui.Color(0x8CD7CCC8),
        ),
      );
    }
  }

  void _spawnLandingBurst(BarrageFxState state) {
    final hoofY = state.y + state.entryHeight / 2 + _mountBottom(state) * 0.92;
    for (int i = 0; i < 9; i++) {
      final r = fxRand01(state.seed, 200 + i * 13);
      final dir = i.isEven ? -1 : 1;
      state.emit(
        BarrageFxParticle(
          x: state.x + state.entryWidth * 0.5 + state.entryWidth * 0.42 - _bodyLength(state) * 0.45 + dir * 14,
          y: hoofY - 2,
          vx: dir * (40 + r * 130),
          vy: -(30 + r * 90),
          gravity: 260,
          drag: 0.86,
          maxLife: 0.5 + r * 0.4,
          startSize: 2.5,
          endSize: 8,
          color: const ui.Color(0x99D7CCC8),
        ),
      );
    }
  }

  void _spawnStreaks(BarrageFxState state, double v) {
    final h = state.entryHeight;
    state.emit(
      BarrageFxParticle(
        x: state.x + state.entryWidth * 0.05,
        y: state.y + h * (0.2 + fxRand01(state.seed, state.elapsed * 17) * 0.6),
        vx: -v * 1.1,
        vy: 0,
        maxLife: 0.28,
        startSize: 2.2,
        endSize: 0.4,
        color: const ui.Color(0x66FFFFFF),
      ),
    );
  }

  /// Total mount height below the danmaku center (local coordinates, legs included).
  double _mountBottom(BarrageFxState state) {
    final bodyH = _bodyHeight(state);
    return state.entryHeight * 0.5 + 2 + bodyH * 0.32 + bodyH * 0.35 + bodyH * 1.15;
  }

  double _bodyLength(BarrageFxState state) =>
      (state.entryWidth * 0.26).clamp(58.0, 100.0);

  double _bodyHeight(BarrageFxState state) =>
      (_bodyLength(state) * 0.42).clamp(10.0, 17.0);

  // ---- Mount drawing ----

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final w = state.entryWidth;
    final h = state.entryHeight;

    final bodyLen = _bodyLength(state);
    final bodyH = _bodyHeight(state);
    final saddleY = h * 0.5 + 2;
    // Mount sits under the FRONT part of the text so the head and muzzle
    // clear the text's leading edge instead of hiding behind it.
    final bc = ui.Offset(w * 0.42 - bodyLen * 0.45, saddleY + bodyH * 0.32);

    final bodyPaint = ui.Paint()..color = fxA(const ui.Color(0xFFB07043), a);
    final darkPaint = ui.Paint()
      ..color = fxA(const ui.Color(0xFF7A4A28), a)
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = (bodyH * 0.30).clamp(3.0, 6.0)
      ..isAntiAlias = true;

    final gallop = state.mem[_kGallopPhase] * math.pi * 2;

    // Tail: three swaying segments.
    _drawTail(canvas, state, bc, bodyLen, bodyH, darkPaint, gallop);

    // Far-side legs (drawn first, behind the body).
    _drawLeg(canvas, bc, bodyLen, bodyH, gallop + math.pi, true, darkPaint);
    _drawLeg(canvas, bc, bodyLen, bodyH, gallop + math.pi * 1.8, false, darkPaint);

    // Body.
    canvas.drawOval(
      ui.Rect.fromCenter(center: bc, width: bodyLen, height: bodyH * 1.35),
      bodyPaint,
    );

    // Saddle cloth: red with a gold trim, peeking out under the text.
    final blanket = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(bc.dx - bodyLen * 0.06, saddleY - 2, bodyLen * 0.36, bodyH * 0.62),
      ui.Radius.circular(bodyH * 0.16),
    );
    canvas.drawRRect(blanket, ui.Paint()..color = fxA(const ui.Color(0xFFD84315), a));
    canvas.drawRect(
      ui.Rect.fromLTWH(bc.dx - bodyLen * 0.06, saddleY - 2 + bodyH * 0.5, bodyLen * 0.36, 1.6),
      ui.Paint()..color = fxA(const ui.Color(0xFFFFD54F), a),
    );

    // Neck + head: a quad neck, a forward-leaning oval head, ears and a dark mane.
    _drawNeckAndHead(canvas, state, bc, bodyLen, bodyH, saddleY, bodyPaint, darkPaint);

    // Near-side legs (drawn last, in front of the body).
    _drawLeg(canvas, bc, bodyLen, bodyH, gallop, false, darkPaint);
    _drawLeg(canvas, bc, bodyLen, bodyH, gallop + math.pi * 0.8, true, darkPaint);
  }

  void _drawNeckAndHead(
    ui.Canvas canvas,
    BarrageFxState state,
    ui.Offset bc,
    double bodyLen,
    double bodyH,
    double saddleY,
    ui.Paint bodyPaint,
    ui.Paint darkPaint,
  ) {
    final a = state.alpha;
    final neckBase = ui.Offset(bc.dx + bodyLen * 0.42, bc.dy - bodyH * 0.15);
    final headCenter = ui.Offset(bc.dx + bodyLen * 0.56, saddleY - bodyH * 0.55);

    final neck = ui.Path()
      ..moveTo(bc.dx + bodyLen * 0.30, bc.dy - bodyH * 0.45)
      ..lineTo(neckBase.dx, neckBase.dy - bodyH * 0.35)
      ..lineTo(headCenter.dx, headCenter.dy + bodyH * 0.18)
      ..lineTo(bc.dx + bodyLen * 0.52, bc.dy - bodyH * 0.55)
      ..close();
    canvas.drawPath(neck, bodyPaint);

    // Mane: a row of short ribbons along the back of the neck.
    for (int i = 0; i < 3; i++) {
      final sway = math.sin(state.elapsed * 5 + i * 0.9) * 0.16;
      final from = ui.Offset(
        headCenter.dx - bodyLen * (0.10 + i * 0.055),
        headCenter.dy + bodyH * (0.10 + i * 0.16),
      );
      canvas.drawLine(from, from + ui.Offset(-bodyH * 0.34 - sway * 8, bodyH * 0.42), darkPaint);
    }

    // Head (forward-leaning oval) + ears + muzzle.
    canvas.save();
    canvas.translate(headCenter.dx, headCenter.dy);
    canvas.rotate(-0.45);
    canvas.drawOval(
      ui.Rect.fromCenter(center: ui.Offset.zero, width: bodyLen * 0.26, height: bodyH * 0.62),
      bodyPaint,
    );
    canvas.drawCircle(
      ui.Offset(bodyLen * 0.115, bodyH * 0.10),
      bodyH * 0.20,
      ui.Paint()..color = fxA(const ui.Color(0xFF4E342A), a),
    );
    // Ears.
    final ear = ui.Path()
      ..moveTo(-bodyLen * 0.02, -bodyH * 0.28)
      ..lineTo(-bodyLen * 0.06, -bodyH * 0.52)
      ..lineTo(-bodyLen * 0.08, -bodyH * 0.24)
      ..close();
    canvas.drawPath(ear, bodyPaint);
    canvas.restore();
  }

  void _drawTail(
    ui.Canvas canvas,
    BarrageFxState state,
    ui.Offset bc,
    double bodyLen,
    double bodyH,
    ui.Paint darkPaint,
    double gallop,
  ) {
    var pos = ui.Offset(bc.dx - bodyLen * 0.48, bc.dy - bodyH * 0.2);
    var angle = math.pi * 0.82;
    for (int i = 0; i < 3; i++) {
      angle += math.sin(state.elapsed * 4 + i * 0.8 - gallop * 0.15) * 0.2;
      final next = pos + ui.Offset(math.cos(angle), math.sin(angle)) * bodyH * 0.52;
      darkPaint.strokeWidth = (bodyH * 0.30 - i * 0.8).clamp(2.4, 6.0);
      canvas.drawLine(pos, next, darkPaint);
      pos = next;
    }
  }

  /// One two-segment leg. [front] selects front/rear; [phaseOffset] places the
  /// leg's hoof-fall within the gait cycle.
  void _drawLeg(
    ui.Canvas canvas,
    ui.Offset bc,
    double bodyLen,
    double bodyH,
    double phase,
    bool front,
    ui.Paint paint,
  ) {
    final joint = ui.Offset(
      bc.dx + (front ? bodyLen * 0.30 : -bodyLen * 0.32),
      bc.dy + bodyH * 0.22,
    );
    final base = front ? 0.14 : -0.14;
    final swing = math.sin(phase) * 0.55;
    final upper = base + swing;
    final legLen = bodyH * 1.15;
    final knee = joint + ui.Offset(math.sin(upper), math.cos(upper)) * (legLen * 0.55);
    final lower = upper + (base >= 0 ? 0.4 : -0.4) + 0.45 * math.cos(phase + 1.1);
    final hoof = knee + ui.Offset(math.sin(lower), math.cos(lower)) * (legLen * 0.5);
    canvas.drawLine(joint, knee, paint);
    canvas.drawLine(knee, hoof, paint);
  }
}
