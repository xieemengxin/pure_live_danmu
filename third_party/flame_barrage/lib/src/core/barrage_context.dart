import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;

import '../cache/render_cache.dart';
import '../effect/motion/barrage_fx_particle.dart';
import '../model/barrage/barrage_entry.dart';
import '../pool/barrage_pool.dart';
import '../render/barrage/mixed_renderer.dart';
import '../scheduler/track_manager.dart';
import 'engine_clock.dart';
import 'barrage_config.dart';
import '../atlas/emoji_atlas.dart';
import '../layout/mixed_layout.dart';
import '../layout/rich_parser.dart';

/// Shared state that every danmaku system reads and mutates.
///
/// One object wires together the configuration, the engine clock, the pooled
/// artifacts and the live entry list, and is handed to each system so no
/// system has to depend on the engine host itself. The host ([BarrageEngine])
/// keeps only lifecycle concerns: frame scheduling, app lifecycle and the
/// public API surface.
class BarrageContext {
  BarrageContext({required BarrageConfig config, required this.emojiAtlas})
    : config = config,
      clock = EngineClock(),
      _renderCache = RenderCache(
        maxSize: config.pictureCacheMaxSize,
        maxBytes: config.rasterCacheMaxBytes,
      ),
      _pool = BarragePool(maxSize: config.barragePoolMaxSize);

  BarrageConfig config;
  final EngineClock clock;
  final EmojiAtlas emojiAtlas;

  // ========================
  // Viewport (filled in by the host on load/resize)
  // ========================

  /// Flame viewport size in logical pixels.
  final Vector2 viewport = Vector2.zero();

  /// Top safe-area inset plus the configured [BarrageConfig.topAreaDistance];
  /// the y origin of the danmaku area.
  double topOffset = 0;

  /// Bottom safe-area inset plus [BarrageConfig.bottomAreaDistance]; the
  /// anchor from which bottom-pinned lanes stack upwards.
  double bottomOffset = 0;

  /// Danmaku area height after safe-area and margin insets. The configured
  /// [BarrageConfig.area] percentage is applied by [TrackManager], not here,
  /// so the percentage is not applied twice.
  double allowedHeight = 0;

  // ========================
  // Pure-logic subsystems (policies and caches)
  // ========================

  late final RichParser parser = RichParser(atlas: emojiAtlas, maxCacheSize: config.textCacheMaxSize);
  late final MixedLayout layout = MixedLayout(atlas: emojiAtlas, maxTextCacheSize: config.textCacheMaxSize);
  late final MixedRenderer renderer = const MixedRenderer();
  final TrackManager trackManager = TrackManager();

  RenderCache get renderCache => _renderCache;
  final RenderCache _renderCache;

  BarragePool get pool => _pool;
  final BarragePool _pool;

  /// Motion-effect particles (hoof dust, contrails, sparks, smoke...).
  /// Advanced by the motion system, drawn under the entries by the render
  /// system. Kept here so effect code never needs a back-reference to a
  /// Flame component.
  final BarrageFxParticleSystem fxParticles = BarrageFxParticleSystem();

  // ========================
  // Live entries (single source of truth)
  // ========================

  /// Entries currently on screen. Systems share it: the data system appends,
  /// the motion system advances and swap-removes, the metrics system
  /// aggregates, the render system draws. Entry order carries no meaning
  /// (lane allocation keeps items from overlapping), which is what makes
  /// tail-swap removal safe.
  final List<BarrageEntry> activeEntries = <BarrageEntry>[];

  /// Number of live entries — the count a display frame actually pays for.
  int aliveCount = 0;

  // ========================
  // Bitmap baking parameters (maintained by the host)
  // ========================

  /// Device pixels per logical pixel that baked bitmaps are produced at, so
  /// text stays as crisp as the vector path on high density panels.
  double rasterScale = 1.0;

  /// Reused for every blit so the steady-state render loop allocates nothing
  /// but the destination offset.
  final ui.Paint imagePaint = ui.Paint()
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.low;
}
