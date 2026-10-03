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

    /// 自己的那条是否已经在屏上：把它撤掉，看屏上少没少一条。
    bool ownIsOnScreen(BarrageController controller) {
      final before = controller.activeItemCount;
      controller.retractWhere((item) => item.priority == selfDanmakuPriority);
      return controller.activeItemCount == before - 1;
    }

    testWidgets('前面排着上百条别人的：自己的插队，下一步就上屏', (tester) async {
      final controller = await _pumpEngine(tester, config: busyRoom);
      for (var i = 0; i < 119; i++) {
        controller.send(BarrageItem(content: '别人的弹幕 $i'));
      }
      controller.send(_own);

      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 17));

      expect(controller.pendingMessageCount, greaterThanOrEqualTo(115), reason: '别人的照常按节奏排队');
      expect(ownIsOnScreen(controller), isTrue);
    });

    testWidgets('没有优先级的同一条消息：半秒后仍排在上百条之后', (tester) async {
      final controller = await _pumpEngine(tester, config: busyRoom);
      for (var i = 0; i < 119; i++) {
        controller.send(BarrageItem(content: '别人的弹幕 $i'));
      }
      controller.send(const BarrageItem(content: '排队的那条', fixedDuration: selfDanmakuCacheMarker));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(controller.activeItemCount, lessThanOrEqualTo(11), reason: '先进先出，每 0.05 秒才放一条');
      expect(controller.pendingMessageCount, greaterThanOrEqualTo(100));
    });

    testWidgets('屏上已到同屏上限：自己的仍然上屏', (tester) async {
      final controller = await _pumpEngine(tester, config: busyRoom.copyWith(maxVisibleCount: 2, realtimeMode: true));
      controller
        ..send(const BarrageItem(content: '别人一'))
        ..send(const BarrageItem(content: '别人二'))
        ..send(const BarrageItem(content: '别人三'));
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 17));
      expect(controller.activeItemCount, 2, reason: '普通弹幕受同屏上限约束');

      controller.send(_own);
      await tester.pump(const Duration(milliseconds: 17));
      expect(controller.activeItemCount, 3);
      expect(ownIsOnScreen(controller), isTrue);
    });

    testWidgets('所有轨道都刚被占住：自己的等到有轨道空出来再上，不和别人叠在一起', (tester) async {
      // 400 高、轨道高 100：四条轨道。
      final controller = await _pumpEngine(
        tester,
        config: busyRoom.copyWith(realtimeMode: true, trackHeight: 100, baseSpeed: 200, fontSize: 20),
      );
      for (var i = 0; i < 4; i++) {
        controller.send(BarrageItem(content: '把这一条轨道的入口占住的一条长弹幕 $i'));
      }
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 17));
      expect(controller.activeItemCount, 4);

      controller.send(_own);
      await tester.pump(const Duration(milliseconds: 17));
      expect(controller.activeItemCount, 4, reason: '没有空轨道时不硬塞');
      expect(controller.pendingMessageCount, 1);

      // 前面的弹幕滚进去、让出入口之后，自己的拿到第一条空出来的轨道。
      for (var i = 0; i < 80 && controller.pendingMessageCount > 0; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.pendingMessageCount, 0);
      expect(ownIsOnScreen(controller), isTrue);
    });
  });
}
