import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_frame_pacing.dart';

/// 用真实引擎跑 [frames] 个显示帧，返回每一帧引擎有没有推进一次逻辑步。
///
/// 帧时间戳按刷新率 [hz] 的屏幕生成：第 k 帧在 floor(k·1e6/hz) 微秒，和 Flame
/// 游戏循环拿到的整微秒帧间隔一致（60 Hz 下是 16666/16667 交替）。
Future<List<bool>> _stepsPerFrame(WidgetTester tester, {required int cap, required double hz, int frames = 120}) async {
  final controller = BarrageController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 800,
          height: 400,
          child: FlameBarrageWidget(
            controller: controller,
            emojiAtlas: EmojiAtlas.instance,
            // 速度放慢到整段测试里这条弹幕都留在屏上，引擎不会因为空闲而停表。
            config: BarrageConfig(fps: danmakuEngineFps(cap), baseSpeed: 20, rasterizeItems: false),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  controller.send(const BarrageItem(content: '帧节奏'));

  final engine = controller.engine! as BarrageEngine;
  var elapsedUs = 0;
  Future<void> nextFrame(int k) async {
    final target = (k * Duration.microsecondsPerSecond / hz).floor();
    await tester.pump(Duration(microseconds: target - elapsedUs));
    elapsedUs = target;
  }

  // 前几帧让引擎完成启动（Flame 第一帧的帧间隔固定为 0）。
  const warmup = 10;
  for (var k = 1; k <= warmup; k++) {
    await nextFrame(k);
  }
  final stepped = <bool>[];
  for (var k = warmup + 1; k <= warmup + frames; k++) {
    final before = engine.frameStepCount;
    await nextFrame(k);
    stepped.add(engine.frameStepCount > before);
  }
  expect(engine.activeCount, 1, reason: '弹幕应当全程在屏上');
  return stepped;
}

/// 相邻两次逻辑步之间隔了多少个显示帧。
List<int> _gaps(List<bool> stepped) {
  final gaps = <int>[];
  int? last;
  for (var i = 0; i < stepped.length; i++) {
    if (!stepped[i]) continue;
    if (last != null) gaps.add(i - last);
    last = i;
  }
  return gaps;
}

void main() {
  // 每个用例：帧率上限、屏幕刷新率、期望“每隔几个显示帧走一步”。
  const cases = <(int cap, double hz, int everyNthFrame)>[
    (60, 60, 1),
    (60, 120, 2),
    (120, 120, 1),
    (30, 60, 2),
    (60, 90, 2),
    (60, 144, 3),
    (144, 144, 1),
  ];

  for (final (cap, hz, nth) in cases) {
    testWidgets('上限 $cap FPS、屏幕 ${hz.toInt()} Hz：弹幕每 $nth 帧匀速走一步', (tester) async {
      final gaps = _gaps(await _stepsPerFrame(tester, cap: cap, hz: hz));
      expect(gaps, isNotEmpty);
      expect(gaps.toSet(), {nth}, reason: '步进间隔不一致就是停一帧再跳两帧的顿挫');
    });
  }
}
