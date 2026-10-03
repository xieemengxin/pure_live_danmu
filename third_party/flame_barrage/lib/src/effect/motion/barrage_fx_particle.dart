import 'dart:ui' as ui;

/// A single effect particle. All fields are mutable; [BarrageFxParticleSystem]
/// advances and recycles particles in bulk.
///
/// A particle does the cheapest thing possible: linear motion with gravity
/// and drag, rendered as a solid circle that scales and fades over its
/// lifetime. Dust puffs, trails, sparks, smoke and flashes are all
/// combinations of these parameters — no image assets involved.
class BarrageFxParticle {
  BarrageFxParticle({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.gravity = 0,
    this.drag = 1.0,
    required this.maxLife,
    this.startSize = 3,
    this.endSize = 0,
    this.color = const ui.Color(0xFFFFFFFF),
  }) : life = maxLife;

  double x;
  double y;

  /// Velocity in px/s.
  double vx;
  double vy;

  /// Acceleration in px/s², positive pointing down. Smoke runs negative to
  /// rise, dust positive to settle.
  double gravity;

  /// Fraction of velocity kept per second (1 = no drag, 0.9 = 10% decay
  /// per second).
  double drag;

  double life;
  double maxLife;

  /// Radius at spawn and death, in px; interpolated linearly.
  double startSize;
  double endSize;

  /// ARGB color; an extra alpha factor from the remaining lifetime is
  /// applied at render time.
  ui.Color color;
}

/// Particle pool shared by every motion effect. Effects spawn into it and
/// the render system draws the whole batch once underneath all danmaku
/// bitmaps.
///
/// Capacity is capped at [maxParticles]: motion effects are rare, showy
/// events and a couple of simultaneous performances amount to a few hundred
/// particles. When full, the oldest particle is dropped rather than letting
/// the list grow unbounded.
class BarrageFxParticleSystem {
  static const int maxParticles = 700;

  final List<BarrageFxParticle> _particles = <BarrageFxParticle>[];

  int get length => _particles.length;
  bool get hasAlive => _particles.isNotEmpty;

  void spawn(BarrageFxParticle particle) {
    if (_particles.length >= maxParticles) {
      _removeAt(0);
    }
    _particles.add(particle);
  }

  void advance(double dt) {
    if (dt <= 0) return;
    final dragFactor = dt.clamp(0.0, 0.2);
    int len = _particles.length;
    int i = 0;
    while (i < len) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _removeAt(i);
        len--;
        continue;
      }
      // Semi-implicit Euler: acceleration first, then drag, so even a dt
      // spike cannot fling a particle away.
      p.vy += p.gravity * dt;
      final damp = 1.0 - (1.0 - p.drag) * dragFactor;
      p.vx *= damp;
      p.vy *= damp;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      i++;
    }
  }

  /// Drawn underneath every danmaku bitmap. One shared paint is recolored
  /// per particle, so steady-state rendering allocates nothing.
  void render(ui.Canvas canvas) {
    final len = _particles.length;
    if (len == 0) return;
    final paint = ui.Paint()..isAntiAlias = true;
    for (int i = 0; i < len; i++) {
      final p = _particles[i];
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final radius = ui.lerpDouble(p.endSize, p.startSize, t) ?? p.startSize;
      if (radius <= 0.01) continue;
      paint.color = p.color.withValues(alpha: p.color.a * t);
      canvas.drawCircle(ui.Offset(p.x, p.y), radius, paint);
    }
  }

  void clear() => _particles.clear();

  void _removeAt(int index) {
    final len = _particles.length - 1;
    _particles[index] = _particles[len];
    _particles.length = len;
  }
}
