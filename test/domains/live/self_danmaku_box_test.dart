import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/self_danmaku_box.dart';

const BarrageConfig _config = BarrageConfig(effectInterceptors: selfDanmakuInterceptors, rasterizeItems: false);

/// 自己发的那条：和 `DanmakuManager.sendDanmaku` 给引擎的标识一致。
const BarrageItem _own = BarrageItem(
  content: '666',
  priority: selfDanmakuPriority,
  fixedDuration: selfDanmakuCacheMarker,
);
const BarrageItem _someoneElse = BarrageItem(content: '666');

Future<BarrageController> _pumpEngine(WidgetTester tester, {BarrageConfig config = _config}) async {
  final controller = BarrageController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 800,
          height: 400,
          child: FlameBarrageWidget(controller: controller, emojiAtlas: EmojiAtlas.instance, config: config),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

/// 让引擎把排队的消息都排上屏（默认每 0.1 秒上屏一条）。
Future<void> _dispatch(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('只拦截自己发的弹幕', () {
    const interceptor = SelfDanmakuBoxInterceptor();
    expect(interceptor.shouldIntercept(_own, _config), isTrue);
    expect(interceptor.shouldIntercept(_someoneElse, _config), isFalse);
  });

  test('引擎排版时：自己的用带方框的绘制，别人同样内容的不受影响', () {
    final layout = MixedLayout(atlas: EmojiAtlas.instance);
    const fragments = <Fragment>[TextFragment('666')];

    final own = layout.layout(fragments, item: _own, config: _config);
    final other = layout.layout(fragments, item: _someoneElse, config: _config);
    final ownAgain = layout.layout(fragments, item: _own, config: _config);

    expect(own.spans.single, isA<SelfDanmakuBoxSpan>());
    expect(other.spans.single.runtimeType, TextLayoutSpan, reason: '同样的文字不能复用带方框的排版');
    expect(identical(ownAgain, own), isTrue, reason: '自己的排版结果单独缓存');
  });

  test('方框留在引擎给每条弹幕位图预留的 8 px 边距之内', () {
    final layout = MixedLayout(atlas: EmojiAtlas.instance);
    final result = layout.layout(const <Fragment>[TextFragment('自己发的')], item: _own, config: _config);
    final span = result.spans.single as SelfDanmakuBoxSpan;
    final reach = SelfDanmakuBoxSpan.boxInset + SelfDanmakuBoxSpan.boxStrokeWidth / 2;

    expect(reach, lessThan(8));
    expect(span.boxRect.left, -SelfDanmakuBoxSpan.boxInset);
    expect(span.boxRect.right, result.width + SelfDanmakuBoxSpan.boxInset);
    expect(span.boxRect.height, result.height);
  });

  testWidgets('画出来的左边线是方框的颜色', (tester) async {
    final layout = MixedLayout(atlas: EmojiAtlas.instance);
    final result = layout.layout(const <Fragment>[TextFragment('666')], item: _own, config: _config);
    final span = result.spans.single as SelfDanmakuBoxSpan;

    const margin = 8.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..translate(margin, margin);
    span.paint(canvas);
    final picture = recorder.endRecording();

    final ByteData pixels = (await tester.runAsync<ByteData?>(() async {
      final image = await picture.toImage((result.width + margin * 2).ceil(), (result.height + margin * 2).ceil());
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    final rowWidth = (result.width + margin * 2).ceil();
    final x = (margin - SelfDanmakuBoxSpan.boxInset).round();
    final y = (margin + result.height / 2).round();
    final offset = (y * rowWidth + x) * 4;
    final r = pixels.getUint8(offset), g = pixels.getUint8(offset + 1), b = pixels.getUint8(offset + 2);

    expect(pixels.getUint8(offset + 3), greaterThan(0), reason: '左边线上应当有颜色');
    expect(g, greaterThan(r), reason: '方框是绿色的');
    expect(g, greaterThan(b));
  });

  testWidgets('位图缓存：自己的和别人同样内容的各用一份', (tester) async {
    final controller = await _pumpEngine(tester);
    controller
      ..send(_someoneElse)
      ..send(_own);
    await _dispatch(tester);

    expect(controller.activeItemCount, 2);
    expect(controller.pictureCacheCount, 2, reason: '共用一份的话方框会丢失，或者出现在别人的弹幕上');
  });

  testWidgets('位图缓存：别人发的同样内容照旧共用一份', (tester) async {
    final controller = await _pumpEngine(tester);
    controller
      ..send(_someoneElse)
      ..send(_someoneElse);
    await _dispatch(tester);

    expect(controller.activeItemCount, 2);
    expect(controller.pictureCacheCount, 1);
  });

  group('弹幕很多时自己发的那条', () {
    // 房间主画面用的排队参数：每 0.05 秒上屏一条，最多排 120 条。
    const busyRoom = BarrageConfig(
      effectInterceptors: selfDanmakuInterceptors,
      rasterizeItems: false,
      emitInterval: 0.05,
      maxVisibleCount: 48,
      maxPendingCount: 120,
    );

    testWidgets('和别人排同一个队：半秒后前面还有上百条，轮不到它', (tester) async {
      final controller = await _pumpEngine(tester, config: busyRoom);
      for (var i = 0; i < 119; i++) {
        controller.send(BarrageItem(content: '别人的弹幕 $i'));
      }
      controller.send(_own);

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(controller.activeItemCount, lessThanOrEqualTo(11), reason: '先进先出，每 0.05 秒才放一条');
      expect(controller.pendingMessageCount, greaterThanOrEqualTo(100), reason: '自己的那条还排在队尾');
    });

    testWidgets('走单独一层：前面没有别人，下一帧就上屏', (tester) async {
      final controller = await _pumpEngine(tester, config: selfDanmakuLayerConfig(busyRoom));
      controller.send(_own);

      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 17));

      expect(controller.activeItemCount, 1);
      expect(controller.pendingMessageCount, 0);
    });

    test('单独一层沿用主画面的样式，只改排队方式', () {
      final layer = selfDanmakuLayerConfig(busyRoom.copyWith(fontSize: 22, baseSpeed: 160));
      expect(layer.fontSize, 22);
      expect(layer.baseSpeed, 160);
      expect(layer.realtimeMode, isTrue);
      expect(identical(layer.effectInterceptors, selfDanmakuInterceptors), isTrue, reason: '方框仍然生效');
    });
  });
}
