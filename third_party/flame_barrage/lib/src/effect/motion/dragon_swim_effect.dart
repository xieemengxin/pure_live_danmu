import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Dragon swim: a multi-segment golden dragon drawn with Canvas primitives
/// carries the message in from the left, its serpentine body undulating along
/// a traveling wave with fins, horns, whiskers and eyes, scattering golden
///
/// scale glints before sweeping out the right side. The head sits below the
/// message center; the twelve segments follow a phase-traveling sine wave
/// that grows toward the tail, the way a serpent swims.
///
/// * Entrance (0-1.0s) — scale bounces 0.55 to 1, opacity ramps up fast;
/// * Cruise — steady swimming with a full-body wave, gold scales glinting in
///   alternation, scale-glint particles dropping below the body;
/// * Exit (last 1.2s) — speed up 1.8x, wave amplitude up 70%, fading out over
///   the final 0.5s.
class DragonSwimEffect extends BarrageMotionEffect {
  const DragonSwimEffect({this.duration = 9.0});

  @override
  final double duration;

  // mem: 0=current speed 1=cruise speed 2=cruise base y 3=wave amplitude multiplier (grows on exit)
  static const int _kSpeed = 0;
  static const int _kCruise = 1;
  static const int _kBaseY = 2;
  static const int _kAmpScale = 3;

  static const int _segCount = 12;
  static const double _entranceEnd = 1.0;

  @override
  void onSpawn(BarrageFxState state) {
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    final travel = state.viewportWidth + state.entryWidth + _bodyLength(state) + 140;
    state.mem[_kBaseY] = baseY;
    state.mem[_kCruise] = travel / (duration + 0.26);
    state.mem[_kSpeed] = state.mem[_kCruise] * 0.55;
    state.mem[_kAmpScale] = 1;
    state.x = -(state.entryWidth + _bodyLength(state)) - 40;
    state.y = baseY;
    state.scale = 0.55;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;

    double target = state.mem[_kCruise];
    if (t < _entranceEnd) {
      state.scale = 0.55 + 0.45 * fxEaseOutBack(t / _entranceEnd);
      state.alpha = (t / 0.35).clamp(0.0, 1.0);
    } else if (t > duration - 1.2) {
      final p = fxClamp01((t - (duration - 1.2)) / 1.2);
      target = state.mem[_kCruise] * 1.8;
      state.mem[_kAmpScale] = 1 + 0.7 * p;
      state.alpha = p > 0.58 ? 1 - (p - 0.58) / 0.42 : 1;
    } else {
      state.scale = 1;
      state.alpha = 1;
    }

    final newV = state.mem[_kSpeed] + (target - state.mem[_kSpeed]) * math.min(1.0, dt * 2.2);
    state.mem[_kSpeed] = newV;
    state.x += newV * dt;
    state.y = state.mem[_kBaseY] + math.sin(t * 1.4 + state.seed * 5) * 2.5;

    _spawnScales(state, dt);
  }

  // ---- Geometry ----

  double _spacing(BarrageFxState state) => (state.entryHeight * 0.62).clamp(18.0, 28.0);

  double _bodyLength(BarrageFxState state) => _spacing(state) * _segCount;

  double _headRadius(BarrageFxState state) =>
      (state.entryHeight * 0.42).clamp(11.0, 18.0);

  /// Local coordinates of segment [i] (0 is the head). The wave's phase travels
  /// toward the tail and the amplitude grows toward it.
  ui.Offset _segment(BarrageFxState state, int i) {
    // Head leads just past the text's front edge so the face stays visible.
    final headX = state.entryWidth * 0.5 + _headRadius(state) * 0.6;
    final headY = state.entryHeight * 0.55;
    final amp = state.entryHeight * 0.30 * state.mem[_kAmpScale];
    final profile = 0.4 + 0.6 * i / _segCount;
    final wave = math.sin(state.elapsed * 2.6 - i * 0.55 + state.seed * 6) * amp * profile;
    return ui.Offset(headX - i * _spacing(state), headY + wave);
  }

  void _spawnScales(BarrageFxState state, double dt) {
    // About 8 glints per second: a metronome picks a segment and drops a golden
    // scale glint from its position.
    final emitAcc = state.mem[4] + dt * 8;
    if (emitAcc >= 1) {
      state.mem[4] = emitAcc - emitAcc.floorToDouble();
      final i = (state.elapsed * 8).floor() % _segCount;
      final seg = _segment(state, i);
      final r = fxRand01(state.seed, state.elapsed * 97 + i);
      state.emit(
        BarrageFxParticle(
          x: state.x + seg.dx + (r - 0.5) * 8,
          y: state.y + seg.dy + 4,
          vx: (r - 0.5) * 30 - state.mem[_kSpeed] * 0.1,
          vy: 20 + r * 40,
          gravity: 70,
          drag: 0.96,
          maxLife: 0.6 + r * 0.5,
          startSize: 1.8,
          endSize: 0.3,
          color: r > 0.5 ? const ui.Color(0xFFFFD54F) : const ui.Color(0xFFFFCA28),
        ),
      );
    } else {
      state.mem[4] = emitAcc;
    }
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    final a = state.alpha;
    final headR = _headRadius(state);

    final goldPaint = ui.Paint();
    final outlinePaint = ui.Paint();
    final finPaint = ui.Paint()..color = fxA(const ui.Color(0xFFE65100), a);

    // Draw from tail to head so the head lands on top.
    for (int i = _segCount - 1; i >= 1; i--) {
      final seg = _segment(state, i);
      final r = headR * (1 - i / _segCount * 0.72);
      // Dorsal fins: sharp triangles on alternating segments, behind the scales.
      if (i >= 2 && i <= 10 && i.isEven) {
        final fin = ui.Path()
          ..moveTo(seg.dx - r * 0.7, seg.dy - r * 0.55)
          ..lineTo(seg.dx - r * 0.1, seg.dy - r * 1.75)
          ..lineTo(seg.dx + r * 0.6, seg.dy - r * 0.55)
          ..close();
        canvas.drawPath(fin, finPaint);
      }
      // Scales: dark outline + two alternating golds.
      outlinePaint.color = fxA(const ui.Color(0xFF8D6E08), a);
      canvas.drawCircle(seg, r + 1.4, outlinePaint);
      goldPaint.color = fxA(
        (i.isEven ? const ui.Color(0xFFFFC107) : const ui.Color(0xFFFFB300)),
        a,
      );
      canvas.drawCircle(seg, r, goldPaint);
      // Belly highlight.
      goldPaint.color = fxA(const ui.Color(0x66FFE082), a);
      canvas.drawCircle(ui.Offset(seg.dx + r * 0.15, seg.dy + r * 0.35), r * 0.55, goldPaint);
    }

    _paintHead(canvas, state, headR, a);
  }

  void _paintHead(ui.Canvas canvas, BarrageFxState state, double headR, double a) {
    final head = _segment(state, 0);
    final outlinePaint = ui.Paint()..color = fxA(const ui.Color(0xFF8D6E08), a);
    final goldPaint = ui.Paint()..color = fxA(const ui.Color(0xFFFFC107), a);
    final darkPaint = ui.Paint()
      ..color = fxA(const ui.Color(0xFF4E342A), a)
      ..strokeWidth = headR * 0.22
      ..strokeCap = ui.StrokeCap.round;

    // Horns: two swept-back curves.
    for (final dir in <double>[-0.35, 0.3]) {
      final horn = ui.Path()
        ..moveTo(head.dx - headR * 0.1, head.dy - headR * 0.7)
        ..quadraticBezierTo(
          head.dx - headR * 0.9 + dir * headR,
          head.dy - headR * 1.7,
          head.dx - headR * 1.5 + dir * headR,
          head.dy - headR * 1.15,
        );
      canvas.drawPath(horn, darkPaint..style = ui.PaintingStyle.stroke);
    }

    // Head + snout.
    canvas.drawCircle(head, headR + 1.4, outlinePaint);
    canvas.drawCircle(head, headR, goldPaint);
    canvas.drawCircle(
      ui.Offset(head.dx + headR * 0.82, head.dy + headR * 0.30),
      headR * 0.5,
      goldPaint,
    );
    canvas.drawCircle(
      ui.Offset(head.dx + headR * 0.82, head.dy + headR * 0.30),
      headR * 0.5 + 1.2,
      outlinePaint,
    );

    // Eye.
    canvas.drawCircle(
      ui.Offset(head.dx + headR * 0.30, head.dy - headR * 0.28),
      headR * 0.30,
      ui.Paint()..color = fxA(const ui.Color(0xFFFFFFFF), a),
    );
    canvas.drawCircle(
      ui.Offset(head.dx + headR * 0.40, head.dy - headR * 0.24),
      headR * 0.15,
      ui.Paint()..color = fxA(const ui.Color(0xFF212121), a),
    );

    // Whiskers: two long bezier whiskers trailing backward.
    final whiskerPaint = ui.Paint()
      ..color = fxA(const ui.Color(0xFFFF6F00), a)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = headR * 0.18
      ..strokeCap = ui.StrokeCap.round;
    for (final dir in <double>[-1, 1]) {
      final sway = math.sin(state.elapsed * 3 + dir) * headR * 0.5;
      final whisker = ui.Path()
        ..moveTo(head.dx + headR * 1.1, head.dy + headR * 0.42)
        ..quadraticBezierTo(
          head.dx + headR * (1.9 + dir * 0.2),
          head.dy + headR * (0.9 + dir * 0.6) + sway * 0.4,
          head.dx + headR * (1.3 + dir * 0.5),
          head.dy + headR * (1.8 + dir * 0.4) + sway,
        );
      canvas.drawPath(whisker, whiskerPaint);
    }
  }
}
