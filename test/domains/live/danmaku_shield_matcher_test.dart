import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/danmaku_shield_matcher.dart';

void main() {
  test('普通屏蔽词：包含即屏蔽，不分大小写', () {
    final matcher = DanmakuShieldMatcher(['抽奖', ' VIP ']);
    expect(matcher.matches('今晚抽奖啦'), isTrue);
    expect(matcher.matches('买个vip吧'), isTrue);
    expect(matcher.matches('普通弹幕'), isFalse);
  });

  test('写成 /.../ 的是正则（Simple Live 的写法），区分大小写', () {
    final matcher = DanmakuShieldMatcher([r'/\d{6,}/', '/^QQ/']);
    expect(matcher.matches('加群 12345678'), isTrue);
    expect(matcher.matches('12345'), isFalse);
    expect(matcher.matches('QQ联系'), isTrue);
    expect(matcher.matches('qq联系'), isFalse);
    expect(matcher.matches(r'这句话里有 /\d{6,}/ 这段字'), isFalse, reason: '正则条目不再当普通文字匹配');
  });

  test('写错的正则被忽略，不影响其它规则', () {
    final matcher = DanmakuShieldMatcher(['/([/', '抽奖']);
    expect(matcher.matches('抽奖'), isTrue);
    expect(matcher.matches('(['), isFalse);
  });

  test('单独的斜杠和空条目不算规则', () {
    final matcher = DanmakuShieldMatcher(['', '  ', '//']);
    expect(matcher.matches('随便什么'), isFalse);
    expect(matcher.matches('a//b'), isTrue, reason: '"//" 太短不是正则，按普通文字匹配');
    expect(DanmakuShieldMatcher.none.matches('随便什么'), isFalse);
  });
}
