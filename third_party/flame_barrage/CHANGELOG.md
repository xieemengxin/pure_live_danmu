# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## 0.0.8

### Fixed - motion smoothness on high-fps displays

- **Frame driver rebuilt on Flame's own game loop.** The previous custom pulse ticker + phase accumulator clamped frame durations at three separate layers (ticker delta, step time, engine `dt`) and quantized the motion clock to whole milliseconds. Whenever the actual frame time exceeded a clamp bound (video decode load, 59.94 Hz panels, `fps` set above the display refresh rate), each step advanced less real time than actually elapsed - scroll speed visibly sagged and jumped. The engine now runs on Flame's display-synced loop with microsecond-precision dt, and every logic step advances the clock by the **real** elapsed time; only post-suspend gaps (>150 ms) are clamped. Velocity is uniform by construction.
- **Microsecond motion clock.** `EngineClock.nowPrecise()` and a double-precision `BarrageEntry.lastUpdateTime` remove the +-0.5 ms integer rounding that jittered per-frame position deltas at high step rates.
- **Realtime (unthrottled) dispatch.** New `BarrageConfig.realtimeMode`: bypasses the `emitInterval` pacing and drains the whole waiting queue every logic frame (still bounded by `maxVisibleCount` and lane availability), so burst messages appear the moment they arrive instead of trailing the queue. Exposed in the example config panel.
- **Tap-to-hold interaction.** New `pauseItemAt(x, y)` / `resumeAllPaused()` / `pausedCount` on the controller and engine API: a held message freezes in place (neither scrolling nor expiring; pinned dwell time does not run out), so the host can open an action sheet — block user, report, like — and release it afterwards to continue from the exact spot. Demoed in `TapPauseDemoScreen`.
- **Live config restyling.** `updateConfig` now detects style-affecting changes (font, colors, stroke, shadow, opacity, emoji size, rasterization, interceptors) and lane-geometry changes (track height/area/safe area) and rebuilds every on-screen message immediately via `BarrageDataSystem.relayoutActive` - scrolling items keep their x, pinned items re-center under the new geometry, and pooled artifacts are exchanged by reference count. Speed/buffer-only changes still leave on-screen items untouched.

### Architecture - system-based engine refactor

- **Systems instead of a god class.** The ~900-line `BarrageEngine` was split into four Flame system components that run in a fixed priority order each frame, following a data -> motion -> metrics -> render pipeline:
  - `BarrageDataSystem` (priority 100) - waiting queue, emit pacing, a staged prepare-ahead pipeline (pending -> prepared -> active, warms parse/layout for up to 3 queue-head messages per frame instead of only the head) and lane allocation on dispatch.
  - `BarrageMotionSystem` (priority 200) - scroll motion and fixed-item expiry with **immediate swap-remove recycling**: expired entries leave the list the same frame and return to the pool, replacing the old 0.5 s periodic sweep that let dead entries linger (and be traversed by render/hit-testing).
  - `BarrageMetricsSystem` (priority 300) - per-lane density/avg-speed/youngest-edge aggregation (~30 Hz).
  - `BarrageRenderSystem` (priority 400) - the flat bitmap blit / vector fallback plus `entryAt` hit-testing.
  All shared state (config, engine clock, tracks, pools, caches, the live entry list) now lives in a single `BarrageContext`; the engine host keeps only assembly, frame driving and app lifecycle.
- **Typed engine API.** Added abstract `BarrageEngineApi`; `BarrageEngine implements BarrageEngineApi` and `BarrageController` now forwards calls through the typed interface. The old `dynamic`-based callback indirection (and its try/catch guards) is gone; the public controller methods are unchanged.
- **Playback rate.** New `BarrageEngine.playbackRate` (getter/setter) scaling the engine clock. Affects scroll speed and fixed-item dwell time together.
- **Overload watchdog.** Every logic frame is timed; when a step exceeds 20 ms a throttled warning is logged, and `BarrageEngine.lastStepCostUs` / `peakStepCostUs` expose the cost to metrics surfaces.
- **Removed dead code.** `BarrageComponent`, `BarrageLayer`, `BarrageOverlay` and `OverlapDetector` were unreachable (the engine has rendered from a flat entry list since 0.0.5) and are now deleted together with their exports.

### Breaking changes

- `BarrageEntry.lastUpdateTime` changed from `int` to `double` (sub-millisecond motion precision).
- `BarrageComponent`, `BarrageLayer`, `BarrageOverlay` and `OverlapDetector` were removed from the public exports.

## 0.0.7

### Performance - TV / low-end device rendering (rasterized barrage bitmaps)

- **Barrage bitmaps.** Each message is now baked once into a GPU-resident bitmap at device resolution (`BarrageConfig.rasterizeItems`, default `true`) and drawn as a single textured quad per frame, instead of replaying its text, stroke, shadow and emoji display list on every display frame. Stroked glyph runs were being re-tessellated by the raster thread on every one of those replays, which made a full screen of danmaku drop frames on TV-class hardware. Measured on a 1080p scene with ~74 messages on screen (Windows/Impeller): raster time per frame p50 **1.99 ms -> 0.82 ms**, p90 **2.19 ms -> 1.04 ms**, at a cost of 8.3 MB of bitmap memory.
- Added `BarrageConfig.rasterizeItems` and `BarrageConfig.rasterCacheMaxBytes` (default 24 MB) for bitmap baking and its GPU memory budget.
- Only messages up to 4096 device pixels per side are baked; longer messages and platforms without picture rasterization fall back to the vector path automatically.
- **Fixed a latent crash/stutter source.** LRU eviction used to dispose pictures that visible messages were still drawing, so a stream with more distinct messages than the cache holds threw on every following frame. The new `RenderCache` is reference counted: an evicted artifact survives until the last barrage using it is recycled, and `clear()` / `updateConfig()` follow the same rule.
- Added `RenderCache` / `CachedRender` (exported). `PictureCache` is kept for compatibility but is no longer used by the engine.
- Added `BarrageEngine.activeCount` / `rasterCacheBytes` and `BarrageController.activeItemCount` / `rasterCacheBytes` to observe on-screen load and bitmap memory.

### Example

- Config panel: new `rasterizeItems` switch; memory screen reports bitmap VRAM usage and the on-screen message count.

## 0.0.6
- Cleaned up formatting and removed unnecessary whitespace in object_pool.dart, picture_pool.dart, emoji_protocol.dart, message_protocol.dart, barrage_renderer.dart, emoji_renderer.dart, mixed_renderer.dart, base_renderer.dart, overlap_detector.dart, speed_strategy.dart, track_allocator.dart, track_manager.dart, barrage_logger.dart, color_util.dart, fps_monitor.dart, measure.dart, barrage_overlay.dart, and flame_barrage_widget.dart.
- Updated the version in pubspec.yaml from 0.0.5 to 0.0.6.
- Enhanced the performance of the speed calculation logic in speed_strategy.dart.
- Improved the track allocation logic in track_allocator.dart to ensure better performance under load.
- Added proper disposal of resources in flame_barrage_widget.dart to prevent memory leaks.

## 0.0.5

- Added per‑track differentiated scroll speed for scrolling barrages.
- Speed is calculated based on track position and current track barrage count, applied on barrage creation.
- Added `useUniformSpeed` flag to `BarrageConfig`, toggle uniform speed mode, default `true` for backward compatibility.
- Added `dynamicSpeedWhileFlying` flag to `BarrageConfig`. When enabled, already flying scroll barrages adjust speed in real‑time according to track status; may cause barrage overlap, default `false`.
- Fixed scroll barrage movement using hard‑coded baseSpeed value, now uses entry.speed.
- Fixed track speed factor not working when track already has barrages.
- Retained original single‑track anti‑overtake logic.

> Note: Differentiated speed only affects newly spawned barrages by default. Already flying barrages retain their initial speed to prevent overlap. Enable `dynamicSpeedWhileFlying` to turn on real‑time speed adjustment.




## 0.0.4

- Added optional pointer event handling for `FlameBarrageWidget`.
- Added `enablePointerEvents` property to control whether the barrage widget responds to mouse and touch events.
- Improved barrage rendering isolation and prevented unnecessary pointer event processing when interaction is disabled.
- Fixed potential rendering artifacts caused by pointer events.

## 0.0.3

- New demo page for multiple screens sharing single BarrageController, support mutual exclusive switch between full screen and small window
- New BarrageItem independent style test demo to verify per-danmaku custom style override
- Add `fontFamily` property to BarrageConfig, BarrageEngine, MixedLayout and BarrageItem, support global and single danmaku custom font configuration
- Complete pause & resume freeze mechanism for barrage engine

## 0.0.2

- Added GitHub Pages online demo.
- Added English / Chinese README navigation.
- Improved documentation.
- Updated project branding and logo.

## 0.0.1

* Initial public release.
* High-performance barrage rendering engine powered by Flame.
* Batch rendering pipeline for reduced Widget Tree overhead.
* Dual-pass text rendering with independent outline and fill passes.
* Zero-allocation object pooling system (`BarragePool`).
* Dynamic runtime configuration updates.
* Native emoji rendering support.
* Sprite atlas animation support.
* Precise barrage interaction callbacks.
* Extensible Fragment architecture for custom rendering components.
* MIT License.
