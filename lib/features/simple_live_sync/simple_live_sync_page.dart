import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/qr_code_widget.dart';
import 'package:pure_live/features/simple_live_sync/simple_live_sync_protocol.dart';
import 'package:pure_live/features/simple_live_sync/simple_live_sync_receiver.dart';

class SimpleLiveSyncPage extends GetView<SimpleLiveSyncReceiver> {
  const SimpleLiveSyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('simple_live_sync'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Obx(() => _buildStatusCard(theme)),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('simple_live_sync_accept')),
          context.buildModernCard([
            context.buildSwitchTile(
              title: i18n('simple_live_sync_follows'),
              subtitle: i18n('simple_live_sync_follows_desc'),
              value: controller.acceptFollows,
              icon: Remix.heart_3_line,
              isLong: true,
            ),
            context.buildSwitchTile(
              title: i18n('simple_live_sync_shield'),
              subtitle: i18n('simple_live_sync_shield_desc'),
              value: controller.acceptShieldWords,
              icon: Remix.filter_3_line,
              isLong: true,
            ),
            context.buildSwitchTile(
              title: i18n('bullet_magazine'),
              subtitle: i18n('simple_live_sync_magazine_desc'),
              value: controller.acceptBulletMagazine,
              icon: Remix.focus_3_line,
              isLong: true,
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('simple_live_sync_log')),
          Obx(() => _buildLog(theme)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final colors = theme.colorScheme;
    final error = controller.errorKey.value;
    final running = controller.running.value;
    final addresses = controller.addresses.toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                error.isNotEmpty
                    ? Remix.error_warning_line
                    : running
                    ? Remix.wifi_line
                    : Remix.loader_4_line,
                color: error.isNotEmpty ? colors.error : colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i18n(
                    error.isNotEmpty
                        ? error
                        : running
                        ? 'simple_live_sync_waiting'
                        : 'simple_live_sync_starting',
                  ),
                  style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (running && addresses.isEmpty) ...[
            const SizedBox(height: 12),
            Text(i18n('simple_live_sync_no_address'), style: AppTextStyles.t13.copyWith(color: colors.error)),
          ],
          if (running && addresses.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrCodeWidget(data: controller.qrPayload, size: 168),
            ),
            const SizedBox(height: 12),
            for (final address in addresses)
              SelectableText(
                address,
                style: AppTextStyles.t18.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            const SizedBox(height: 10),
            Text(
              i18n('simple_live_sync_steps'),
              textAlign: TextAlign.center,
              style: AppTextStyles.t13.copyWith(color: colors.onSurfaceVariant, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLog(ThemeData theme) {
    final events = controller.events.toList(growable: false);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          i18n('simple_live_sync_log_empty'),
          style: AppTextStyles.t13.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final event in events)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Remix.checkbox_circle_line, color: theme.colorScheme.primary),
            title: Text(
              i18n(
                switch (event.kind) {
                  SimpleLiveSyncKind.follows => 'simple_live_sync_got_follows',
                  SimpleLiveSyncKind.shieldWords => 'simple_live_sync_got_shield',
                  SimpleLiveSyncKind.bulletMagazine => 'simple_live_sync_got_magazine',
                },
                args: {'received': '${event.received}', 'added': '${event.added}'},
              ),
            ),
          ),
      ],
    );
  }
}
