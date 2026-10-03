import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Geometry of the six-way quick-danmaku wheel.
///
/// Slot `i` is centred on `i * 60°` counter-clockwise from "right": 0 right,
/// 1 upper right, 2 upper left, 3 left, 4 lower left, 5 lower right.
abstract final class BulletMagazineGeometry {
  static const int slotCount = 6;

  /// A release closer than this to the centre fires nothing.
  static const double deadZone = 30;
  static const double maxRadius = 132;

  /// The wheel is not offered on a player surface narrower than this.
  static const double minSurfaceSide = 240;
  static const double edgeMargin = 10;

  /// Slot under a pointer [delta] away from the wheel centre; null inside the
  /// dead zone. Only the direction matters beyond it.
  static int? slotAt(Offset delta, {double deadZone = BulletMagazineGeometry.deadZone}) {
    if (delta.distance < deadZone) return null;
    final degrees = (math.atan2(-delta.dy, delta.dx) * 180 / math.pi + 360 + 30) % 360;
    return (degrees / 60).floor() % slotCount;
  }

  /// Unit vector from the centre to the middle of [slot], in screen coordinates.
  static Offset directionOf(int slot) {
    final angle = slot * math.pi / 3;
    return Offset(math.cos(angle), -math.sin(angle));
  }

  /// Wheel radius for a player [surface]; null when the surface is too small.
  static double? radiusFor(Size surface) {
    if (surface.shortestSide < minSurfaceSide) return null;
    return math.min(maxRadius, surface.shortestSide / 2 - edgeMargin);
  }

  /// Moves the wheel centre so a wheel of [radius] stays fully inside
  /// [surface]: a press near an edge must not open half a wheel off screen.
  static Offset clampCenter(Offset press, Size surface, double radius) {
    final inset = radius + edgeMargin;
    double clampAxis(double value, double extent) =>
        extent <= inset * 2 ? extent / 2 : value.clamp(inset, extent - inset);
    return Offset(clampAxis(press.dx, surface.width), clampAxis(press.dy, surface.height));
  }
}

/// The wheel itself: a frosted disc, six sectors with their preset text, and a
/// hub drawn as a small revolver cylinder whose chamber lights up with the
/// selected sector. Used on the video while a long-press is held and, with
/// [onSlotTap], as the preset editor.
class BulletMagazineWheel extends StatelessWidget {
  const BulletMagazineWheel({super.key, required this.presets, required this.radius, this.selected, this.onSlotTap});

  final List<String> presets;
  final double radius;
  final int? selected;

  /// Editor mode: every sector is tappable and empty ones show a "+".
  final ValueChanged<int>? onSlotTap;

  static const Color accent = Color(0xFFFFD166);

  double get _hubRadius => radius * 0.25;

  String _presetAt(int slot) => slot < presets.length ? presets[slot].trim() : '';

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final filled = List<bool>.generate(BulletMagazineGeometry.slotCount, (slot) => _presetAt(slot).isNotEmpty);
    final wheel = SizedBox.square(
      dimension: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [Color(0xA6000000), Color(0x80000000)], stops: [0.35, 1]),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _BulletMagazinePainter(selected: selected, filled: filled, hubRadius: _hubRadius),
            ),
          ),
          for (var slot = 0; slot < BulletMagazineGeometry.slotCount; slot++) _buildLabel(context, slot),
        ],
      ),
    );

    final onTap = onSlotTap;
    if (onTap == null) return wheel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final slot = BulletMagazineGeometry.slotAt(
          details.localPosition - Offset(radius, radius),
          deadZone: _hubRadius,
        );
        if (slot != null) onTap(slot);
      },
      child: wheel,
    );
  }

  Widget _buildLabel(BuildContext context, int slot) {
    final text = _presetAt(slot);
    final isSelected = slot == selected;
    final centre = Offset(radius, radius) + BulletMagazineGeometry.directionOf(slot) * (radius * 0.66);
    final width = radius * 0.56;
    final height = radius * 0.44;

    final Widget child;
    if (text.isEmpty) {
      if (onSlotTap == null) return const SizedBox.shrink();
      child = Icon(Icons.add_rounded, size: radius * 0.2, color: Colors.white38);
    } else {
      child = AnimatedScale(
        scale: isSelected ? 1.12 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          // Merged into the ambient style so the app font carries over.
          style: DefaultTextStyle.of(context).style.merge(
            TextStyle(
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              height: 1.2,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              decoration: TextDecoration.none,
              shadows: isSelected ? const [Shadow(color: Color(0x99000000), blurRadius: 6)] : const <Shadow>[],
            ),
          ),
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ),
      );
    }

    return Positioned(
      left: centre.dx - width / 2,
      top: centre.dy - height / 2,
      width: width,
      height: height,
      child: Center(child: child),
    );
  }
}

class _BulletMagazinePainter extends CustomPainter {
  const _BulletMagazinePainter({required this.selected, required this.filled, required this.hubRadius});

  final int? selected;
  final List<bool> filled;
  final double hubRadius;

  static const double _sector = math.pi / 3;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;

    final slot = selected;
    if (slot != null) {
      // Canvas angles run clockwise; slot angles counter-clockwise.
      final start = -slot * _sector - _sector / 2;
      final outer = Rect.fromCircle(center: centre, radius: radius);
      final inner = Rect.fromCircle(center: centre, radius: hubRadius);
      final sector = Path()
        ..arcTo(outer, start, _sector, true)
        ..arcTo(inner, start + _sector, -_sector, false)
        ..close();
      canvas.drawPath(
        sector,
        Paint()
          ..shader = ui.Gradient.radial(
            centre,
            radius,
            [BulletMagazineWheel.accent.withValues(alpha: 0.10), BulletMagazineWheel.accent.withValues(alpha: 0.42)],
            [hubRadius / radius, 1],
          ),
      );
      final rim = Rect.fromCircle(center: centre, radius: radius - 2.5);
      const gap = 0.05;
      canvas.drawArc(
        rim,
        start + gap,
        _sector - gap * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = BulletMagazineWheel.accent.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawArc(
        rim,
        start + gap,
        _sector - gap * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = BulletMagazineWheel.accent,
      );
    }

    final divider = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (var i = 0; i < BulletMagazineGeometry.slotCount; i++) {
      final angle = i * _sector + _sector / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(centre + direction * (hubRadius + 6), centre + direction * (radius - 10), divider);
    }

    canvas.drawCircle(
      centre,
      radius - 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    // Hub: a revolver cylinder seen end-on, one chamber per slot.
    canvas.drawCircle(centre, hubRadius, Paint()..color = const Color(0x59000000));
    canvas.drawCircle(
      centre,
      hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: slot == null ? 0.2 : 0.32),
    );
    for (var i = 0; i < BulletMagazineGeometry.slotCount; i++) {
      final chamber = centre + BulletMagazineGeometry.directionOf(i) * (hubRadius * 0.58);
      final lit = i == slot;
      canvas.drawCircle(
        chamber,
        lit ? hubRadius * 0.17 : hubRadius * 0.12,
        Paint()
          ..color = lit
              ? BulletMagazineWheel.accent
              : Colors.white.withValues(alpha: i < filled.length && filled[i] ? 0.55 : 0.16),
      );
    }
    canvas.drawCircle(centre, hubRadius * 0.1, Paint()..color = Colors.white.withValues(alpha: 0.3));
  }

  @override
  bool shouldRepaint(_BulletMagazinePainter oldDelegate) {
    if (oldDelegate.selected != selected || oldDelegate.hubRadius != hubRadius) return true;
    for (var i = 0; i < filled.length; i++) {
      if (i >= oldDelegate.filled.length || oldDelegate.filled[i] != filled[i]) return true;
    }
    return false;
  }
}

/// One open wheel on the player surface: where it sits and what is selected.
@immutable
class BulletMagazineSession {
  const BulletMagazineSession({required this.center, required this.radius, required this.surface, this.selected});

  /// Wheel centre in the player surface's coordinates.
  final Offset center;
  final double radius;
  final Size surface;
  final int? selected;

  BulletMagazineSession withSelected(int? slot) =>
      BulletMagazineSession(center: center, radius: radius, surface: surface, selected: slot);
}

/// The wheel as shown over the video while the long-press is held, with a
/// caption that spells out what releasing will do.
class BulletMagazineOverlay extends StatelessWidget {
  const BulletMagazineOverlay({
    super.key,
    required this.session,
    required this.presets,
    required this.idleCaption,
    required this.emptyCaption,
  });

  final BulletMagazineSession session;
  final List<String> presets;

  /// Caption while nothing is selected.
  final String idleCaption;

  /// Caption when no preset is set at all.
  final String emptyCaption;

  static const double _captionHeight = 34;
  static const double _captionGap = 10;

  @override
  Widget build(BuildContext context) {
    final radius = session.radius;
    final slot = session.selected;
    final hasPresets = presets.any((preset) => preset.trim().isNotEmpty);
    final caption = slot != null && slot < presets.length
        ? presets[slot].trim()
        : hasPresets
        ? idleCaption
        : emptyCaption;

    // The caption goes under the wheel, or above it when the wheel sits at
    // the bottom of the surface.
    final below = session.center.dy + radius + _captionGap + _captionHeight <= session.surface.height;
    final captionTop = below
        ? session.center.dy + radius + _captionGap
        : session.center.dy - radius - _captionGap - _captionHeight;
    // Centred under the wheel, kept inside the surface.
    final captionWidth = math.min(radius * 2.6, session.surface.width - 8);
    final captionLeft = (session.center.dx - captionWidth / 2).clamp(4.0, session.surface.width - captionWidth - 4);

    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: session.center.dx - radius,
              top: session.center.dy - radius,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.82, end: 1),
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: BulletMagazineWheel(presets: presets, radius: radius, selected: slot),
              ),
            ),
            Positioned(
              left: captionLeft,
              width: captionWidth,
              top: captionTop,
              height: _captionHeight,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: slot == null
                          ? Colors.white.withValues(alpha: 0.16)
                          : BulletMagazineWheel.accent.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (slot != null) ...[
                        const Icon(Icons.send_rounded, size: 14, color: BulletMagazineWheel.accent),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: slot == null ? Colors.white70 : Colors.white,
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: slot == null ? FontWeight.w500 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
