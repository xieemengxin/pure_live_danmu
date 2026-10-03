import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/cookie_sanitizer.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_send_message.dart';

/// 虎牙个人中心。未登录时页面自己弹出登录框（扫码、密码、短信），登录成功后整页
/// 刷新，会话 cookie 写在 `huya.com` 域下。
const String huyaWebLoginUrl = 'https://i.huya.com/';

/// 虎牙的登录框是桌面版的固定尺寸 iframe（约 712 px 宽），手机站没有登录入口。窄屏上
/// 把它钉到视口左上角并按屏宽缩放，否则登录框落在屏幕外面。
const String huyaLoginDialogFitScript = r'''
(() => {
  if (window.top !== window || screen.width >= 720) return;
  const dialogWidth = 720;
  const fit = () => {
    const frame = [...document.querySelectorAll('iframe')].find((f) => /udb_login\.html/.test(f.src) && f.offsetWidth > 0);
    if (!frame) return;
    const viewport = window.visualViewport ? window.visualViewport.width : window.innerWidth;
    const style = frame.style;
    style.position = 'fixed';
    style.left = '0';
    style.top = '0';
    style.zIndex = '2147483647';
    style.transformOrigin = '0 0';
    style.transform = 'scale(' + viewport / dialogWidth + ')';
  };
  setInterval(fit, 500);
})();
''';

typedef HuyaWebCookieLoader = Future<String> Function();
typedef HuyaWebCookieClearer = Future<void> Function();
typedef HuyaWebCookieSaver = void Function(String cookie);
typedef HuyaWebLoginCompletion = void Function();

/// 在应用内的浏览器里走虎牙自己的登录页，登录后把会话 cookie 取回来保存。
class HuyaWebLoginController extends GetxController {
  HuyaWebLoginController({
    HuyaWebCookieLoader? cookieLoader,
    HuyaWebCookieClearer? cookieClearer,
    HuyaWebCookieSaver? saveCookie,
    HuyaWebLoginCompletion? completeLogin,
  }) : _cookieLoader = cookieLoader ?? _loadBrowserCookie,
       _cookieClearer = cookieClearer ?? clearBrowserSession,
       _saveCookie = saveCookie ?? _storeCookie,
       _completeLogin = completeLogin ?? _finishLogin;

  final HuyaWebCookieLoader _cookieLoader;
  final HuyaWebCookieClearer _cookieClearer;
  final HuyaWebCookieSaver _saveCookie;
  final HuyaWebLoginCompletion _completeLogin;

  /// 浏览器里上一次的虎牙会话清掉之后才加载登录页。
  final ready = false.obs;
  final isChecking = false.obs;
  final errorMessageKey = ''.obs;

  Future<void>? _activeCheck;
  bool _completed = false;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    // 打开这个页面就是要（重新）登录。浏览器里留着的旧会话可能已经过期，不清掉的话
    // 页面一加载就会被当成"已登录"，取回来的还是那份失效的 cookie。
    try {
      await _cookieClearer();
    } catch (_) {
      // 清不掉也照常登录；最坏是沿用浏览器里已有的会话。
    }
    if (!_closed) ready.value = true;
  }

  /// 每次页面加载完都看一眼：登录成功后页面会刷新，这时 cookie 已经写好。
  void onLoadStop(InAppWebViewController _, WebUri? _) {
    unawaited(checkLogin());
  }

  /// "我已登录"按钮：页面没刷新时由观众手动确认，取不到会话就给出提示。
  Future<void> confirmLogin() => checkLogin(reportMissing: true);

  Future<void> checkLogin({bool reportMissing = false}) {
    if (_closed || _completed) return Future.value();
    final active = _activeCheck;
    if (active != null) return active;

    late final Future<void> task;
    task = _harvestSession(reportMissing).whenComplete(() {
      if (identical(_activeCheck, task)) _activeCheck = null;
    });
    _activeCheck = task;
    return task;
  }

  Future<void> _harvestSession(bool reportMissing) async {
    if (reportMissing) {
      isChecking.value = true;
      errorMessageKey.value = '';
    }
    String cookie;
    try {
      cookie = normalizeAccountCookie(await _cookieLoader());
    } catch (_) {
      if (!_closed && reportMissing) _showError('huya_web_login_cookie_failed');
      return;
    }
    if (_closed || _completed) return;
    if (!HuyaViewerCredentials.hasSession(cookie)) {
      if (reportMissing) _showError('huya_web_login_not_detected');
      return;
    }

    _completed = true;
    isChecking.value = false;
    _saveCookie(cookie);
    _completeLogin();
  }

  void _showError(String messageKey) {
    isChecking.value = false;
    errorMessageKey.value = messageKey;
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }

  static Future<String> _loadBrowserCookie() async {
    final cookies = await CookieManager.instance().getCookies(url: WebUri(huyaWebLoginUrl));
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  /// 清掉应用内浏览器里的虎牙会话；退出登录时也用它，否则下次打开登录页会直接
  /// 取回刚退出的那个会话。
  static Future<void> clearBrowserSession() async {
    final manager = CookieManager.instance();
    final url = WebUri(huyaWebLoginUrl);
    // 会话 cookie 写在 `Domain=huya.com` 下，各平台存成 `.huya.com` 或 `huya.com`。
    for (final domain in const <String>['.huya.com', 'huya.com']) {
      await manager.deleteCookies(url: url, domain: domain);
    }
  }

  static void _storeCookie(String cookie) {
    CookieSettingsController.to.huyaCookie.v = cookie;
  }

  static void _finishLogin() {
    Get.back(result: true);
    ToastUtil.show(i18n('huya_web_login_success'));
  }
}
