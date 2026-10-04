import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/danmaku_config_builder.dart';

/// Runs the real engine for [frames] display frames and reports, per frame,
/// whether it took a logic step.
///
/// Frame timestamps are those of a [hz] panel: frame k at floor(k·1e6/hz) µs,
/// the whole-microsecond intervals Flame's game loop sees (16666/16667
/// alternating at 60 Hz).
Future<List<bool>> _stepsPerFrame(
  WidgetTester tester, {
  required int budget,
  required double hz,
  int frames = 120,
}) async {
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
            // Slow enough that the message stays on screen for the whole run,
            // so the engine never idles its loop.
            config: BarrageConfig(fps: danmakuEngineFps(budget), baseSpeed: 20, rasterizeItems: false),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  controller.send(const BarrageItem(content: 'pacing'));

  final engine = controller.engine! as BarrageEngine;
  var elapsedUs = 0;
  Future<void> nextFrame(int k) async {
    final target = (k * Duration.microsecondsPerSecond / hz).floor();
    await tester.pump(Duration(microseconds: target - elapsedUs));
    elapsedUs = target;
  }

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
  expect(engine.activeCount, 1, reason: 'the message must stay on screen throughout');
  return stepped;
}

/// Display frames between consecutive logic steps.
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
  // budget, panel refresh rate, expected "one step every N display frames".
  const cases = <(int budget, double hz, int everyNthFrame)>[
    (60, 60, 1), // auto mode on a 60 Hz TV
    (120, 120, 1), // auto mode on a 120 Hz TV
    (30, 60, 2), // low-end box capped to 30 on a 60 Hz TV
    (50, 50, 1), // PAL panels
    (60, 120, 2),
    (90, 60, 1), // manual budget above the panel rate
  ];

  for (final (budget, hz, nth) in cases) {
    testWidgets('budget $budget fps on a ${hz.toInt()} Hz panel steps evenly every $nth frame(s)', (tester) async {
      final gaps = _gaps(await _stepsPerFrame(tester, budget: budget, hz: hz));
      expect(gaps, isNotEmpty);
      expect(gaps.toSet(), {nth}, reason: 'uneven gaps are a held frame followed by a double jump: visible stutter');
    });
  }
}
