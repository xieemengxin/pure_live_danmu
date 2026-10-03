import 'dart:ui' as ui;

import 'package:flame/components.dart';

import '../cache/render_cache.dart';
import '../effect/motion/barrage_motion_effect.dart';
import '../model/barrage/barrage_entry.dart';
import '../core/barrage_context.dart';

/// Draws every on-screen entry flat onto the canvas and hit-tests taps.
///
/// Rendering runs through the Flame render tree after all logic systems have
/// advanced, so a frame always paints the settled state. Entries with a
/// baked bitmap cost one textured quad each; entries that were never baked
/// (over-long messages, platforms without picture rasterization) fall back
/// to a translate plus a replay of the vector recording.
///
/// Entries running a motion effect ([BarrageEntry.fx]) are drawn through a
/// transform pass instead: particles first (under everything), then the
/// mount painted by the effect, then the message bitmap — translated to the
/// entry center and rotated/scaled/faded per the effect's state. Only the
/// few special entries pay for save/restore.
class BarrageRenderSystem extends Component {
  BarrageRenderSystem(this._ctx, {int priority = 400}) : super(priority: priority);

  final BarrageContext _ctx;

  /// Separate blit paint for fading effect entries: the shared
  /// [BarrageContext.imagePaint] must stay untouched for the steady state.
  /// White base color — the color multiplies the bitmap, so it must start
  /// from "no tint".
  final ui.Paint _fxImagePaint = ui.Paint()
    ..color = const ui.Color(0xFFFFFFFF)
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.low;

  @override
  void render(ui.Canvas canvas) {
    final entries = _ctx.activeEntries;
    final int len = entries.length;
    final ui.Paint paint = _ctx.imagePaint;
    // Effect particles live in world space and sit under every message.
    _ctx.fxParticles.render(canvas);
    // Text/emoji/sprite alpha is baked into each cached artifact by
    // MixedLayout, and with rasterizeItems the whole message is a bitmap, so a
    // frame only blits it. Replaying the vector recording instead re-runs every
    // text, stroke, shadow and emoji op per display frame — stroked glyphs are
    // re-tessellated on each of those replays, which is what makes a full
    // screen of danmaku miss a 144 Hz deadline on TV-class hardware.
    for (int i = 0; i < len; i++) {
      final entry = entries[i];
      final fx = entry.fx;
      if (fx != null) {
        _drawEffectEntry(canvas, entry, fx, paint);
        continue;
      }
      final render = entry.render;
      final image = render?.image;
      if (image != null) {
        final current = render!;
        if (current.oneToOne) {
          canvas.drawImage(image, ui.Offset(entry.x - current.padding, entry.y - current.padding), paint);
        } else {
          canvas.drawImageRect(
            image,
            current.rasterSrc,
            ui.Rect.fromLTWH(
              entry.x - current.padding,
              entry.y - current.padding,
              current.rasterWidth,
              current.rasterHeight,
            ),
            paint,
          );
        }
        continue;
      }

      final picture = entry.picture;
      if (picture == null) continue;
      canvas.save();
      canvas.translate(entry.x, entry.y);
      canvas.drawPicture(picture);
      canvas.restore();
    }
  }

  /// Draws one motion-effect entry: mount under the bitmap, both wrapped in
  /// the effect's rotation/scale around the entry center. Alpha only applies
  /// to the blitted bitmap — the rare unpictured fallback ignores it (a
  /// saveLayer for those would cost more than it is worth).
  void _drawEffectEntry(ui.Canvas canvas, BarrageEntry entry, BarrageFxState fx, ui.Paint paint) {
    final effect = fx.effect;
    if (effect == null) return;
    final render = entry.render;
    canvas.save();
    canvas.translate(entry.x + entry.width / 2, entry.y + entry.height / 2);
    if (fx.rotation != 0) canvas.rotate(fx.rotation);
    if (fx.scale != 1) canvas.scale(fx.scale, fx.scale);

    effect.paint(canvas, fx);

    final image = render?.image;
    if (image != null) {
      final current = render!;
      if (fx.alpha >= 0.999) {
        _blitCentered(canvas, image, current, paint);
      } else {
        _fxImagePaint.color = const ui.Color(0xFFFFFFFF).withValues(alpha: fx.alpha);
        _blitCentered(canvas, image, current, _fxImagePaint);
      }
    } else {
      final picture = entry.picture;
      if (picture != null) {
        canvas.save();
        canvas.translate(-entry.width / 2, -entry.height / 2);
        canvas.drawPicture(picture);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  void _blitCentered(ui.Canvas canvas, ui.Image image, CachedRender current, ui.Paint blit) {
    if (current.oneToOne) {
      canvas.drawImage(image, ui.Offset(-current.rasterWidth / 2, -current.rasterHeight / 2), blit);
    } else {
      canvas.drawImageRect(
        image,
        current.rasterSrc,
        ui.Rect.fromLTWH(
          -current.rasterWidth / 2,
          -current.rasterHeight / 2,
          current.rasterWidth,
          current.rasterHeight,
        ),
        blit,
      );
    }
  }

  /// Returns the top-most active entry at [x]/[y], or null. Iteration runs
  /// back-to-front so later entries win, matching visual stacking.
  BarrageEntry? entryAt(double x, double y) {
    final entries = _ctx.activeEntries;
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (x < entry.x || x > entry.x + entry.width || y < entry.y || y > entry.y + entry.height) {
        continue;
      }
      return entry;
    }
    return null;
  }
}
