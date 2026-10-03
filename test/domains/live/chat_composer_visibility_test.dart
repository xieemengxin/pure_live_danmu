import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_message_actions.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller_panel.dart';

void main() {
  test('已登录能发到平台时，关掉本地互动也显示输入框', () {
    expect(shouldShowFullscreenLocalDanmakuComposer(false, postsChatToPlatform: true), isTrue);
  });

  test('只能发本地字幕时，输入框跟随本地互动开关', () {
    expect(shouldShowFullscreenLocalDanmakuComposer(true), isTrue);
    expect(shouldShowFullscreenLocalDanmakuComposer(false), isFalse);
  });

  test('全屏时底部输入栏随键盘上移；非全屏的播放器不动', () {
    expect(fullscreenKeyboardLift(fullscreen: true, keyboardInset: 216), 216);
    expect(fullscreenKeyboardLift(fullscreen: true, keyboardInset: 0), 0);
    expect(fullscreenKeyboardLift(fullscreen: false, keyboardInset: 216), 0);
  });

  group('+1', () {
    LiveMessage message(String text, {LiveMessageType type = LiveMessageType.chat}) =>
        LiveMessage(type: type, userName: '观众', message: text, color: LiveMessageColor.white);

    test('能发到平台时，聊天弹幕可以 +1', () {
      expect(DanmakuMessageActions.canPlusOne(message('666'), postsChatToPlatform: true), isTrue);
    });

    test('没登录（发不到平台）时不提供 +1', () {
      expect(DanmakuMessageActions.canPlusOne(message('666'), postsChatToPlatform: false), isFalse);
    });

    test('没有文字的消息、礼物等非聊天消息不提供 +1', () {
      expect(DanmakuMessageActions.canPlusOne(message('  '), postsChatToPlatform: true), isFalse);
      expect(
        DanmakuMessageActions.canPlusOne(message('送出火箭', type: LiveMessageType.gift), postsChatToPlatform: true),
        isFalse,
      );
    });
  });
}
