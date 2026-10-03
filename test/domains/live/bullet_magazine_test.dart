import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/bullet_magazine/bullet_magazine_wheel.dart';

void main() {
  group('方向判定', () {
    test('离中心太近不选任何一格', () {
      expect(BulletMagazineGeometry.slotAt(Offset.zero), isNull);
      expect(BulletMagazineGeometry.slotAt(const Offset(20, 20)), isNull);
    });

    test('六个方向依次是 右、右上、左上、左、左下、右下（与 Simple Live 的顺序一致）', () {
      // 屏幕坐标 y 向下，所以“上”是负的 dy。
      expect(BulletMagazineGeometry.slotAt(const Offset(100, 0)), 0);
      expect(BulletMagazineGeometry.slotAt(const Offset(50, -87)), 1);
      expect(BulletMagazineGeometry.slotAt(const Offset(-50, -87)), 2);
      expect(BulletMagazineGeometry.slotAt(const Offset(-100, 0)), 3);
      expect(BulletMagazineGeometry.slotAt(const Offset(-50, 87)), 4);
      expect(BulletMagazineGeometry.slotAt(const Offset(50, 87)), 5);
    });

    test('只看方向：拖出转盘之外仍然选中', () {
      expect(BulletMagazineGeometry.slotAt(const Offset(900, 10)), 0);
    });

    test('每一格的中心方向落在它自己那一格里', () {
      for (var slot = 0; slot < BulletMagazineGeometry.slotCount; slot++) {
        expect(BulletMagazineGeometry.slotAt(BulletMagazineGeometry.directionOf(slot) * 80), slot);
      }
    });
  });

  group('转盘位置', () {
    test('画面太小不提供弹匣', () {
      expect(BulletMagazineGeometry.radiusFor(const Size(393, 221)), isNull);
    });

    test('横屏全屏用完整大小，较窄的画面按短边缩小', () {
      expect(BulletMagazineGeometry.radiusFor(const Size(852, 393)), BulletMagazineGeometry.maxRadius);
      expect(BulletMagazineGeometry.radiusFor(const Size(600, 250)), 115);
    });

    test('靠边长按时把转盘挪回画面里', () {
      const surface = Size(852, 393);
      const radius = 132.0;
      final inset = radius + BulletMagazineGeometry.edgeMargin;

      expect(BulletMagazineGeometry.clampCenter(const Offset(5, 5), surface, radius), Offset(inset, inset));
      expect(
        BulletMagazineGeometry.clampCenter(const Offset(850, 390), surface, radius),
        Offset(surface.width - inset, surface.height - inset),
      );
      expect(BulletMagazineGeometry.clampCenter(const Offset(400, 196), surface, radius), const Offset(400, 196));
    });
  });

  group('预设整理', () {
    test('总是正好六条：缺的补空，多的丢掉，去掉首尾空白', () {
      expect(DanmakuSettingsController.normalizeBulletMagazinePresets(null), ['', '', '', '', '', '']);
      expect(DanmakuSettingsController.normalizeBulletMagazinePresets([' 666 ', null, 3]), [
        '666',
        '',
        '3',
        '',
        '',
        '',
      ]);
      expect(DanmakuSettingsController.normalizeBulletMagazinePresets(['1', '2', '3', '4', '5', '6', '7']), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
    });

    test('超过长度上限的截断，按字符算不按字节算', () {
      final long = '弹' * 30;
      final normalized = DanmakuSettingsController.normalizeBulletMagazinePresets([long]);
      expect(normalized.first, '弹' * DanmakuSettingsController.bulletMagazineMaxLength);
    });
  });

  testWidgets('编辑器：点哪一格就编辑哪一格，点中心不触发', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BulletMagazineWheel(presets: const ['666', '', '', '', '', ''], radius: 120, onSlotTap: tapped.add),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(BulletMagazineWheel));

    await tester.tapAt(centre + const Offset(80, 0));
    await tester.tapAt(centre + const Offset(-40, 70));
    await tester.tapAt(centre);

    expect(tapped, [0, 4]);
    expect(find.text('666'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNWidgets(5), reason: '编辑时空的格子显示加号');
  });

  testWidgets('画面上的转盘：选中后说明文字显示将要发送的内容', (tester) async {
    const surface = Size(800, 400);
    Widget overlay(int? selected) => MaterialApp(
      home: Material(
        child: BulletMagazineOverlay(
          session: BulletMagazineSession(
            center: const Offset(400, 180),
            radius: 132,
            surface: surface,
            selected: selected,
          ),
          presets: const ['666', '主播好厉害', '', '', '', ''],
          idleCaption: '滑向一格，松手发送',
          emptyCaption: '还没有预设',
        ),
      ),
    );

    await tester.pumpWidget(overlay(null));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('滑向一格，松手发送'), findsOneWidget);

    await tester.pumpWidget(overlay(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('滑向一格，松手发送'), findsNothing);
    expect(find.text('主播好厉害'), findsNWidgets(2), reason: '扇区里一份，说明文字里一份');
  });
}
