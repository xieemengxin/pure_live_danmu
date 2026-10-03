library;

// animation
export 'src/animation/combo_animation.dart';
export 'src/animation/sprite_animation_player.dart';

// atlas
export 'src/atlas/atlas_loader.dart';
export 'src/atlas/emoji_atlas.dart';
export 'src/atlas/sprite_sheet.dart';

// cache
export 'src/cache/atlas_cache.dart';
export 'src/cache/picture_cache.dart';
export 'src/cache/render_cache.dart';
export 'src/cache/sprite_cache.dart';
export 'src/cache/text_cache.dart';

// core
export 'src/core/barrage_config.dart';
export 'src/core/barrage_context.dart';
export 'src/core/barrage_controller.dart';
export 'src/core/barrage_engine.dart';
export 'src/core/barrage_engine_api.dart';

// effect
export 'src/effect/glow_effect.dart';
export 'src/effect/gradient_effect.dart';
export 'src/effect/shadow_effect.dart';
export 'src/effect/stroke_effect.dart';
export 'src/effect/barrage_effect_interceptor.dart';

// effect/motion — effect danmaku (entrance/cruise/exit choreography, hand-drawn mounts, particles)
export 'src/effect/motion/barrage_fx_particle.dart';
export 'src/effect/motion/barrage_motion_effect.dart';
export 'src/effect/motion/airplane_effect.dart';
export 'src/effect/motion/dragon_swim_effect.dart';
export 'src/effect/motion/ghost_drift_effect.dart';
export 'src/effect/motion/horse_riding_effect.dart';
export 'src/effect/motion/magic_carpet_effect.dart';
export 'src/effect/motion/meteor_streak_effect.dart';
export 'src/effect/motion/rocket_launch_effect.dart';
export 'src/effect/motion/ufo_effect.dart';

// layout
export 'src/layout/emoji_fragment.dart';
export 'src/layout/emoji_layout_span.dart';
export 'src/layout/fragment.dart';
export 'src/layout/layout_result.dart';
export 'src/layout/layout_span.dart';
export 'src/layout/mixed_layout.dart';
export 'src/layout/rich_parser.dart';
export 'src/layout/text_fragment.dart';
export 'src/layout/sprite_layout_span.dart';
export 'src/layout/sprite_fragment.dart';

// model/barrage
export 'src/model/barrage/barrage_entry.dart';
export 'src/model/barrage/barrage_item.dart';
export 'src/model/barrage/barrage_track.dart';
export 'src/model/barrage/barrage_type.dart';

// model/emoji
export 'src/model/emoji/emogi_source_type.dart';
export 'src/model/emoji/emoji_info.dart';

// model/base
export 'src/model/base_message.dart';

// pool
export 'src/pool/barrage_pool.dart';
export 'src/pool/object_pool.dart';
export 'src/pool/picture_pool.dart';

// protocol
export 'src/protocol/emoji_protocol.dart';
export 'src/protocol/message_protocol.dart';

// render/barrage
export 'src/render/barrage/barrage_renderer.dart';
export 'src/render/barrage/emoji_renderer.dart';
export 'src/render/barrage/mixed_renderer.dart';

// render/base
export 'src/render/base_renderer.dart';

// scheduler
export 'src/scheduler/speed_strategy.dart';
export 'src/scheduler/track_allocator.dart';
export 'src/scheduler/track_manager.dart';

// systems
export 'src/systems/barrage_data_system.dart';
export 'src/systems/barrage_metrics_system.dart';
export 'src/systems/barrage_motion_system.dart';
export 'src/systems/barrage_render_system.dart';

// util
export 'src/util/barrage_logger.dart';
export 'src/util/color_util.dart';
export 'src/util/fps_monitor.dart';
export 'src/util/measure.dart';

// widget
export 'src/widget/flame_barrage_widget.dart';
