import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/app_prompt_dialogs.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/bullet_magazine/bullet_magazine_wheel.dart';

/// Preset editor: the same wheel the player shows, on a dark stage so it looks
/// the way it will over a video. Tapping a sector edits that direction.
class BulletMagazineEditor extends StatelessWidget {
  const BulletMagazineEditor({super.key, required this.presets, required this.onChanged});

  final List<String> presets;
  final void Function(int slot, String text) onChanged;

  static const List<String> _directionArrows = <String>['→', '↗', '↖', '←', '↙', '↘'];

  Future<void> _edit(int slot) async {
    final current = slot < presets.length ? presets[slot] : '';
    final result = await AppPromptDialogs.showEditTextDialog(
      current,
      title: i18n('bullet_magazine_edit_title', args: {'direction': _directionArrows[slot]}),
      hintText: i18n(
        'bullet_magazine_edit_hint',
        args: {'count': '${DanmakuSettingsController.bulletMagazineMaxLength}'},
      ),
    );
    if (result == null) return;
    onChanged(slot, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B2F3A), Color(0xFF14161C)],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final radius = ((constraints.maxWidth - 32) / 2)
                    .clamp(96.0, BulletMagazineGeometry.maxRadius)
                    .toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: BulletMagazineWheel(
                      key: const ValueKey('bullet-magazine-editor-wheel'),
                      presets: presets,
                      radius: radius,
                      onSlotTap: _edit,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            i18n('bullet_magazine_editor_tip'),
            textAlign: TextAlign.center,
            style: AppTextStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
