import 'dart:ui' as ui;

import 'package:flame_barrage/flame_barrage.dart';

/// `BarrageItem.priority` of a danmaku the viewer posted to the platform.
///
/// The engine keys its layout cache on the priority, so the boxed layout of an
/// own message is never reused for someone else's message with the same text.
const int selfDanmakuPriority = 1;

/// `BarrageItem.fixedDuration` of an own danmaku.
///
/// The engine shares one baked bitmap between items whose text and style
/// match, and that key does not include the priority: without a difference an
/// own "666" and another viewer's "666" would share a bitmap, and the box would
/// go missing or show up on the wrong one. Own messages always scroll, so the
/// duration itself is unused; one microsecond off the engine default only makes
/// the bitmap key distinct.
const Duration selfDanmakuCacheMarker = Duration(microseconds: 4000001);

/// The engine re-lays out everything on screen when a config carries a
/// different interceptor list instance, so every surface shares this one.
const List<BarrageEffectInterceptor> selfDanmakuInterceptors = <BarrageEffectInterceptor>[SelfDanmakuBoxInterceptor()];

/// Config of the layer that shows only the viewer's own danmaku.
///
/// The engine's waiting queue is first-in first-out: it admits one message per
/// emit interval, stops while the screen is at its cap, and drops whatever has
/// waited too long. In a busy room an own message queued behind everyone
/// else's therefore shows up seconds late or not at all. On a layer of its own
/// nothing is ahead of it, and [BarrageConfig.realtimeMode] puts it on screen
/// on the next frame.
BarrageConfig selfDanmakuLayerConfig(BarrageConfig main) =>
    main.copyWith(realtimeMode: true, maxVisibleCount: 12, maxPendingCount: 12);

/// Draws a box around the viewer's own danmaku so it stands out on the video.
class SelfDanmakuBoxInterceptor extends BarrageEffectInterceptor {
  const SelfDanmakuBoxInterceptor();

  @override
  bool shouldIntercept(BarrageItem item, BarrageConfig config) => item.priority == selfDanmakuPriority;

  @override
  LayoutSpan createCustomSpan({
    required BarrageItem item,
    required String text,
    required ui.Paragraph paragraph,
    required double x,
    required double y,
    required double width,
    required double height,
    required BarrageConfig config,
  }) {
    return SelfDanmakuBoxSpan(
      x: x,
      y: y,
      width: width,
      height: height,
      text: text,
      paragraph: paragraph,
      // The hook only hands over the fill paragraph; the outline has to be
      // rebuilt here or the boxed text would lose its stroke.
      strokeParagraph: config.showStroke ? _buildStrokeParagraph(text, config) : null,
      opacity: config.opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Mirrors the engine's stroke paragraph (`MixedLayout._buildParagraph`) so
  /// the outline lines up with the fill it is drawn under.
  static ui.Paragraph _buildStrokeParagraph(String text, BarrageConfig config) {
    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = config.strokeWidth
      ..color = config.strokeColor.withValues(alpha: config.strokeColor.a * resolveBarrageStrokeOpacity(config.opacity))
      ..isAntiAlias = true;
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: config.fontSize, height: 1.15))
      ..pushStyle(
        ui.TextStyle(
          foreground: strokePaint,
          fontSize: config.fontSize,
          fontWeight: config.fontWeight,
          fontStyle: config.fontStyle,
          fontFamily: config.fontFamily,
          letterSpacing: config.letterSpacing,
        ),
      )
      ..addText(text)
      ..pop();
    return builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  }
}

/// The engine only accepts a custom span that is a [TextLayoutSpan] subclass
/// and re-creates it through [copyWithY] when it centres the line vertically.
class SelfDanmakuBoxSpan extends TextLayoutSpan {
  const SelfDanmakuBoxSpan({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.text,
    required super.paragraph,
    required super.strokeParagraph,
    required this.opacity,
  });

  final double opacity;

  SelfDanmakuBoxSpan copyWithY(double y) => SelfDanmakuBoxSpan(
    x: x,
    y: y,
    width: width,
    height: height,
    text: text,
    paragraph: paragraph,
    strokeParagraph: strokeParagraph,
    opacity: opacity,
  );

  static const ui.Color boxColor = ui.Color(0xFF4CAF50);
  static const double boxStrokeWidth = 1.5;

  /// Gap between the text and the box. The engine pads a message's bitmap by
  /// 8 px on every side, so the box has to stay inside that.
  static const double boxInset = 3.0;

  ui.Rect get boxRect => ui.Rect.fromLTRB(x - boxInset, y, x + width + boxInset, y + height);

  @override
  void paint(ui.Canvas canvas) {
    final stroke = strokeParagraph;
    if (stroke != null) canvas.drawParagraph(stroke, ui.Offset(x, y));
    canvas.drawRect(
      boxRect,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = boxStrokeWidth
        ..color = boxColor.withValues(alpha: opacity)
        ..isAntiAlias = true,
    );
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
  }
}
