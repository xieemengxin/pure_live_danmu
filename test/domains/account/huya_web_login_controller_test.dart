import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/account/presentation/account/huya/huya_web_login_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_send_message.dart';

// 字段名取自一次真实的网页登录（值是编的）：访客状态下只有匿名身份，登录成功后登录
// 接口再写入账号 uid 和会话令牌。
const String _anonymousCookie =
    'guid=0a8926b9c115c16aa002aac0abc0abb7; udb_guiddata=b6e670e4b53d4f27885ab1bb3ccc9147; '
    'udb_anouid=1471352450523; udb_anobiztoken=AQAn1yqKK2SX; udb_passdata=3; udb_appid=5002';
const String _signedInCookie =
    '$_anonymousCookie; udb_cred=ChA0Xss6SE; udb_uid=20240001; yyuid=20240001; udb_passport=viewer; '
    'username=viewer; udb_version=1.0; udb_biztoken=AQBS9GFzvmf0; udb_origin=0; udb_status=1';

void main() {
  group('会话判定', () {
    test('访客 cookie 不算登录', () {
      expect(HuyaViewerCredentials.hasSession(_anonymousCookie), isFalse);
      expect(HuyaViewerCredentials.hasSession(''), isFalse);
    });

    test('有账号 uid 和会话令牌才算登录', () {
      expect(HuyaViewerCredentials.hasSession(_signedInCookie), isTrue);
      expect(HuyaViewerCredentials.hasSession('yyuid=20240001'), isFalse, reason: '只有 uid、没有会话令牌');
      expect(HuyaViewerCredentials.hasSession('udb_biztoken=AQBS9GFzvmf0'), isFalse, reason: '只有令牌、没有 uid');
      expect(HuyaViewerCredentials.hasSession('yyuid=20240001; udb_biztoken='), isFalse, reason: '令牌是空的');
    });
  });

  group('网页登录', () {
    late String browserCookie;
    late List<String> events;
    late List<String> saved;
    late int completions;

    HuyaWebLoginController create({bool loaderFails = false, bool clearerFails = false}) {
      return HuyaWebLoginController(
        cookieLoader: () async {
          if (loaderFails) throw StateError('cookie store unavailable');
          return browserCookie;
        },
        cookieClearer: () async {
          events.add('clear');
          if (clearerFails) throw StateError('cannot clear');
        },
        saveCookie: saved.add,
        completeLogin: () => completions++,
      );
    }

    setUp(() {
      browserCookie = _anonymousCookie;
      events = <String>[];
      saved = <String>[];
      completions = 0;
    });

    test('先清掉浏览器里的旧会话，再允许加载登录页', () async {
      final controller = create();
      expect(controller.ready.value, isFalse);
      controller.onInit();
      await pumpEventQueue();
      expect(events, <String>['clear']);
      expect(controller.ready.value, isTrue);
    });

    test('旧会话清不掉也照常进入登录页', () async {
      final controller = create(clearerFails: true)..onInit();
      await pumpEventQueue();
      expect(controller.ready.value, isTrue);
    });

    test('页面加载完但还没登录：不保存、不提示', () async {
      final controller = create();
      await controller.checkLogin();
      expect(saved, isEmpty);
      expect(completions, 0);
      expect(controller.errorMessageKey.value, '');
    });

    test('登录后页面刷新：取回会话 cookie 并结束，只做一次', () async {
      final controller = create();
      browserCookie = _signedInCookie;
      await controller.checkLogin();
      await controller.checkLogin();
      expect(saved, <String>[_signedInCookie]);
      expect(completions, 1);
    });

    test('点"我已登录"但浏览器里没有会话：给出提示', () async {
      final controller = create();
      await controller.confirmLogin();
      expect(saved, isEmpty);
      expect(controller.errorMessageKey.value, 'huya_web_login_not_detected');
      expect(controller.isChecking.value, isFalse);

      browserCookie = _signedInCookie;
      await controller.confirmLogin();
      expect(saved, <String>[_signedInCookie]);
      expect(completions, 1);
    });

    test('读不到浏览器 cookie：手动确认时提示，自动检查时不打扰', () async {
      final controller = create(loaderFails: true);
      await controller.checkLogin();
      expect(controller.errorMessageKey.value, '');
      await controller.confirmLogin();
      expect(controller.errorMessageKey.value, 'huya_web_login_cookie_failed');
      expect(completions, 0);
    });

    test('页面关闭后不再保存', () async {
      final controller = create();
      controller.onClose();
      browserCookie = _signedInCookie;
      await controller.checkLogin();
      expect(saved, isEmpty);
      expect(completions, 0);
    });
  });
}
