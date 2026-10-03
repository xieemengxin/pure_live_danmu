import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/account/presentation/account/huya/huya_web_login_controller.dart';
import 'package:remixicon/remixicon.dart';

class HuyaWebLoginPage extends GetView<HuyaWebLoginController> {
  const HuyaWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('huya_web_login')),
        actions: [
          Obx(
            () => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                key: const ValueKey('huya-web-login-confirm'),
                onPressed: controller.isChecking.value || !controller.ready.value ? null : controller.confirmLogin,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                child: Text(i18n('huya_web_login_confirm')),
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (!controller.ready.value) {
          return const Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(huyaWebLoginUrl)),
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(source: huyaLoginDialogFitScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
              ]),
              onLoadStop: controller.onLoadStop,
            ),
            if (controller.errorMessageKey.value.isNotEmpty)
              _buildErrorBanner(theme, i18n(controller.errorMessageKey.value)),
          ],
        );
      }),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String message) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            key: const ValueKey('huya-web-login-error'),
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Remix.error_warning_line, color: theme.colorScheme.onErrorContainer, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: AppTextStyles.t13.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
