import 'dart:math' as math;
import 'dart:ui' as ui;

import 'barrage_fx_particle.dart';
import 'barrage_motion_effect.dart';

/// Ghost drift: no mount — the message itself is the ghost. Its opacity
/// breathes in and out as it drifts leisurely right to left, with wisps of
/// white mist rising and dissipating beneath it.
///
/// * Entrance (0-0.8s) — opacity fades in from 0 while a ring of cold glow
///   appears behind the text;
/// * Cruise — sinusoidal bobbing with an opacity pulse (0.2-0.8); the
///   slowest travel speed of the effect set;
/// * Exit (last 1.4s) — opacity falls to zero while white mist rises from below.
class GhostDriftEffect extends BarrageMotionEffect {
  const GhostDriftEffect({this.duration = 7.0});

  @override
  final double duration;

  // mem: 0=cruise base y
  static const int _kBaseY = 0;

  @override
  void onSpawn(BarrageFxState state) {
    final baseY = state.laneTop + (state.laneHeight - state.entryHeight) / 2;
    state.mem[_kBaseY] = baseY;
    state.x = state.viewportWidth + state.entryWidth * 0.5;
    state.y = baseY;
    state.alpha = 0;
  }

  @override
  void advance(BarrageFxState state, double dt) {
    final t = state.elapsed;
    final travel = state.viewportWidth + state.entryWidth * 2;
    final v = travel / duration;

    state.x -= v * dt;
    state.y = state.mem[_kBaseY] + math.sin(t * 1.5 + state.seed * 6.28) * 7;

    // Opacity = fade-in envelope x breathing pulse x fade-out envelope.
    final fadeIn = fxEaseOutCubic(t / 0.8);
    final fadeOut = t > duration - 1.4 ? fxClamp01((duration - t) / 1.4) : 1.0;
    final pulse = 0.5 + 0.3 * math.sin(t * 2.3 + state.seed * 9);
    state.alpha = fadeIn * fadeOut * pulse;

    // Mist: emitted throughout and continuously during the fade, rising from
    // the bottom edge of the text.
    if (fxRand01(state.seed, t * 5.1) < 0.14) {
      final r = fxRand01(state.seed, t * 77);
      state.emit(
        BarrageFxParticle(
          x: state.x + state.entryWidth * (0.1 + r * 0.8),
          y: state.y + state.entryHeight * (0.6 + r * 0.35),
          vx: (r - 0.5) * 20,
          vy: -(20 + r * 26),
          drag: 0.98,
          maxLife: 1.2 + r * 0.8,
          startSize: 2,
          endSize: 6,
          color: const ui.Color(0x40FFFFFF),
        ),
      );
    }
  }

  @override
  void paint(ui.Canvas canvas, BarrageFxState state) {
    // Cold glow: radial light behind the text, breathing with the opacity.
    final a = state.alpha;
    final r = state.entryHeight * 1.5;
    final shader = ui.Gradient.radial(
      ui.Offset.zero,
      r,
      [
        fxA(const ui.Color(0x33E1F5FE), a),
        fxA(const ui.Color(0x00E1F5FE), 0),
      ],
    );
    canvas.drawCircle(ui.Offset.zero, r, ui.Paint()..shader = shader);
  }
}
