<p align="center">
  <a href="./README.md">🇺🇸 English</a> |
  <a href="./README_ZH.md">🇨🇳 简体中文</a>
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/liuchuancong/flame_barrage/refs/heads/main/assets/logo/logo.png" alt="FlameBarrage Engine Logo" width="720">
</p>

<h1 align="center">🔥 FlameBarrage Engine</h1>

<p align="center">
  A High-Performance, Hardware-Accelerated Barrage Rendering Engine for Flutter
</p>

<p align="center">
  <a href="https://pub.dev/packages/flame_barrage">
    <img src="https://img.shields.io/pub/v/flame_barrage.svg" alt="pub version">
  </a>
  <a href="https://github.com/liuchuancong/flame_barrage">
    <img src="https://img.shields.io/badge/GitHub-Repository-black.svg" alt="GitHub">
  </a>
  <a href="https://liuchuancong.github.io/flame_barrage/">
    <img src="https://img.shields.io/badge/Live-Demo-success.svg" alt="Demo">
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.x-blue.svg">
  <img src="https://img.shields.io/badge/Flame-1.38+-orange.svg">
  <img src="https://img.shields.io/badge/License-MIT-green.svg">
</p>

---

## 🎮 Live Demo

👉 **Demo:** https://liuchuancong.github.io/flame_barrage/

The online demo showcases high-performance barrage rendering, live configuration updates, emoji and sprite-sheet rendering, interaction handling and real-time performance testing.

---

## 🚀 Overview

FlameBarrage Engine is a high-performance, hardware-accelerated barrage (danmaku) rendering engine built on top of the Flame graphics framework, designed for live streaming platforms, video comment overlays, esports broadcasts and other high-concurrency real-time scenarios.

Instead of a widget per message, the engine renders from a flat entry list through a small system pipeline:

| System | Priority | Responsibility |
| --- | --- | --- |
| `BarrageDataSystem` | 100 | Waiting queue, emit pacing, pre-layout of queued messages, lane allocation on dispatch |
| `BarrageMotionSystem` | 200 | Scroll integration against the logic clock, expiry, immediate swap-remove recycling |
| `BarrageMetricsSystem` | 300 | Per-lane density / avg-speed / youngest-edge aggregation (~30 Hz) |
| `BarrageRenderSystem` | 400 | One flat blit pass over the canvas, plus hit-testing |

All shared state lives in a single `BarrageContext` (config, logic clock, lanes, pools, caches, live entries). The game loop only runs while there is visible work — a silent room costs nothing — and every logic step advances the clock by the real elapsed time, so scroll velocity is uniform regardless of frame load.

---

## 🔥 Core Features

### ⚡ Batch Rendering Pipeline

Text, emoji and graphic assets are decomposed into lightweight rendering fragments and submitted directly to the low-level canvas — no widgets, no per-message layout, no rebuild churn.

### 🖼️ Rasterized Barrage Bitmaps

Each message is recorded once as a vector display list, then baked into a GPU-resident bitmap at device resolution (`BarrageConfig.rasterizeItems`, on by default). A display frame draws one textured quad per visible message instead of replaying its text, outline, shadow and emoji operations — and a stroked glyph run is re-tessellated on the raster thread on every one of those replays, which is what makes a full screen of danmaku miss its deadline on TV-class hardware.

**Measured on a 1080p scene with ~74 messages on screen** (Windows / Impeller, per-frame raster time): **p50 1.99 ms → 0.82 ms, p90 2.19 ms → 1.04 ms, VRAM cost 8.3 MB**. A synthetic CPU-raster scene of 100 distinct CJK messages drops from 4.63 ms to 2.41 ms per frame.

- Bitmaps are reference counted — a cache eviction never disposes something still on screen
- Bounded by `pictureCacheMaxSize` entries and `rasterCacheMaxBytes` of GPU memory
- Repeated content ("666", welcome templates) shares a single bitmap across every instance
- Messages longer than 4096 device pixels, and platforms without picture rasterization, transparently keep the vector path

### 🎨 Dual-Pass Typography Rendering

Text outlines and fills are rendered as independent paragraphs, avoiding font-cache interference: no first-frame dark artifacts, no outline bleeding, no flicker.

### ♻️ Zero-Allocation Object Pool

`BarragePool` reuses pooled entry objects; expired entries leave the screen the same frame they expire and return to the pool — extremely low GC pressure, stable memory over long sessions.

### 📐 Live Configuration Restyling

`updateConfig` applies changes without clearing the screen. When a change affects what on-screen messages look like or where they sit, every visible message is re-laid out and re-baked immediately: scrolling messages keep their position, pinned messages re-center under the new lane geometry.

### 🎯 Frame-Rate Independent Motion

Positions integrate against a sub-millisecond logic clock using the real elapsed time of each frame — velocity never depends on frame load or clamped step durations. Uniform scrolling at 60/120/144 Hz panels, with lane conflict avoidance and safe-gap control.

### ⏩ Playback Rate & Realtime Dispatch

- `engine.playbackRate` scales the whole logic clock (0.05–8.0): scroll travel and pinned dwell time together.
- `BarrageConfig.realtimeMode` bypasses emit pacing and drains the waiting queue every logic frame (still bounded by `maxVisibleCount` and lane availability) — bursts appear on arrival.

---

## 📦 Installation

```yaml
dependencies:
  flame: ^1.38.2
  flame_barrage: ^0.0.8
```

---

## 🛠 Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flame_barrage/flame_barrage.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key});
  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  final BarrageController _controller = BarrageController();

  final BarrageConfig _config = const BarrageConfig(
    fontSize: 20,
    baseSpeed: 150,
    trackHeight: 44,
    showStroke: true,
    safeArea: true,
    opacity: 0.8,
  );

  @override
  void dispose() {
    _controller.clear();
    _controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: FlameBarrageWidget(
            controller: _controller,
            config: _config,
            emojiAtlas: EmojiAtlas.instance,
          ),
        ),
      ],
    );
  }
}
```

Send a message, update config live, pause/resume:

```dart
_controller.send(BarrageItem(content: 'Hello FlameBarrage!', type: BarrageType.scroll));

_controller.updateConfig(_config.copyWith(fontSize: 24)); // on-screen messages restyle instantly

_controller.pause();
_controller.resume();
_controller.clear();
```

---

## 📖 API Reference

### FlameBarrageWidget

The entry widget. Owns one `BarrageEngine` instance for its lifetime.

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `controller` | `BarrageController` | required | Facade used to send messages and drive the engine |
| `config` | `BarrageConfig` | required | Engine configuration; changes are hot-applied |
| `emojiAtlas` | `EmojiAtlas` | required | Emoji/sprite registry, typically `EmojiAtlas.instance` |
| `enablePointerEvents` | `bool` | `false` | When true, taps/long-presses are hit-tested against barrage items. Without it the surface ignores pointers, so it never steals gestures from an underlying video player |

### BarrageController

Type-safe facade between host code and the engine.

| Member | Signature | Description |
| --- | --- | --- |
| `send` | `void send(BarrageItem item)` | Enqueue a message (no-op while `running == false`) |
| `updateConfig` | `void updateConfig(BarrageConfig config)` | Hot-apply configuration |
| `pause` / `resume` | `void pause()` / `void resume()` | Stop/advance the engine; messages sent while paused buffer instead of dropping |
| `togglePause` | `void togglePause()` | Flip `running` |
| `clear` | `void clear()` | Release every entry, queue and cached artifact |
| `attach` / `detach` | `void attach(BarrageEngineApi engine)` / `void detach([BarrageEngineApi? engine])` | Bind/unbind the engine (done automatically by `FlameBarrageWidget`) |
| `triggerItemAt` | `bool triggerItemAt(double x, double y, {required bool longPress})` | Hit-test a point and fire the top-most matching message's callback; returns false when nothing hit |
| `running` | `bool` | Whether sends and engine advancement are active |
| `totalEmitted` | `int` | Messages accepted by `send` |
| `activeItemCount` | `int` | Messages currently on screen |
| `pendingMessageCount` | `int` | Messages waiting for a lane (incl. pause buffer) |
| `pictureCacheCount` | `int` | Entries in the render cache |
| `rasterCacheBytes` | `int` | GPU bytes held by baked bitmaps |
| `poolObjectCount` | `int` | Entry objects parked in the pool |

### BarrageEngine / BarrageEngineApi

`BarrageEngine extends FlameGame implements BarrageEngineApi`. You normally never construct it directly — `FlameBarrageWidget` does. Use it for playback control and metrics:

```dart
engine.playbackRate = 2.0;          // 0.05–8.0, scales the whole logic clock
engine.activeCount;                 // on-screen messages
engine.pendingMessageCount;         // queued messages
engine.rasterCacheBytes;            // bitmap VRAM usage
engine.activeCacheSize;             // render cache entries
engine.activePoolSize;              // pooled entry objects
engine.rasterizationActive;         // whether bitmaps are being blitted
engine.lastStepCostUs;              // last logic-step cost (µs)
engine.peakStepCostUs;              // peak step cost since last overload warning
engine.parserCacheSize;             // parsed content cache entries
engine.layoutCacheSize;             // layout result cache entries
engine.frameStepCount;              // total logic steps executed
engine.context;                     // advanced: shared BarrageContext
```

A logic step exceeding 20 ms logs a throttled overload warning.

### BarrageItem

The immutable message description.

| Field | Type | Description |
| --- | --- | --- |
| `content` | `String` (required) | Raw text; may embed emoji keys resolved by the atlas regex |
| `type` | `BarrageType` | `scroll` (default) / `topFixed` / `bottomFixed` |
| `priority` | `int` | Higher wins contested lane allocation |
| `userId` / `userName` | `String?` | Sender identity |
| `textColor`, `fontSize`, `fontWeight`, `fontStyle`, `fontFamily`, `letterSpacing` | overrides | Per-message typography (falls back to `BarrageConfig`) |
| `showStroke`, `strokeColor`, `strokeWidth` | overrides | Per-message outline |
| `showShadow`, `shadowColor`, `shadowBlur`, `shadowOffset` | overrides | Per-message shadow |
| `opacity` | `double?` | Per-message alpha |
| `fixedDuration` | `Duration?` | Per-message dwell time for pinned types |
| `emojiSize` | `double?` | Per-message inline emoji size |
| `baseSpeed` | `double?` | Per-message scroll speed |
| `overlapSafeGap` | `double?` | Per-message lane safe gap |
| `effect` | `BarrageMotionEffect?` | Hands the message to a choreographed mount effect (entrance/cruise/exit, hand-drawn mount, particles); it owns a lane for the whole show |
| `cachedFragments`, `cachedLayout`, `cachedPicture` | advanced | Precomputed artifacts that skip the parse/layout/cache stages |
| `onTapDown` / `onTapUp` / `onLongTapDown` / `onTapCancel` | `void Function()?` | Interaction callbacks (require `enablePointerEvents: true` or `triggerItemAt`) |

### BarrageConfig

All engine tuning. Every field is hot-appliable via `copyWith`; style and lane-geometry changes restyle the screen instantly.

<details>
<summary><b>All fields</b></summary>

| Group | Field | Type / Default | Description |
| --- | --- | --- | --- |
| Typography | `fontSize` | `double` / 18 | Baseline font size |
| | `fontWeight` | `FontWeight` / w500 | Baseline weight |
| | `fontStyle` | `FontStyle` / normal | Italic or normal |
| | `fontFamily` | `String?` | Custom font family |
| | `letterSpacing` | `double` / 0 | Extra glyph spacing |
| Color & effects | `textColor` | `Color` / white | Fill color |
| | `showStroke` | `bool` / true | Outline rendering |
| | `strokeColor` / `strokeWidth` | black / 1.0 | Outline look |
| | `showShadow` / `shadowColor` / `shadowBlur` / `shadowOffset` | false / black / 0 / (1,1) | Paragraph shadow (no saveLayer per frame) |
| | `opacity` | `double` / 1.0 | Global alpha |
| Layout | `area` | `double` / 1.0 | Fraction of viewport height usable for lanes |
| | `trackHeight` | `double` / 36 | Lane height (auto-floored to fontSize+10) |
| | `topAreaDistance` / `bottomAreaDistance` | 0 / 0 | Extra insets beyond the safe area |
| | `safeArea` | `bool` / true | Respect `MediaQuery` insets |
| Timing & speed | `fps` | `int` / 60 | Logic-step ceiling; display refresh bounds it in practice |
| | `fixedDuration` | `Duration` / 4s | Dwell time for pinned messages |
| | `baseSpeed` | `double` / 120 | Scroll speed in px/s |
| Dispatch | `emitInterval` | `double` / 0.1 | Seconds between paced dispatches |
| | `realtimeMode` | `bool` / false | Bypass pacing; flush the queue every logic frame |
| | `maxVisibleCount` | `int` / 80 | On-screen message cap |
| | `maxPendingCount` | `int` / 120 | Queue cap (oldest dropped beyond it) |
| | `maxPendingAge` | `Duration` / 5s | Drop messages older than this before dispatch |
| | `overlapSafeGap` | `double` / 40 | Minimum clearance between messages in a lane |
| Resources | `noEmojiMode` | `bool` / false | Render text only, skip all emoji fragments |
| | `barragePoolMaxSize` | `int` / 150 | Entry pool size |
| | `pictureCacheMaxSize` | `int` / 200 | Render cache entry cap |
| | `rasterCacheMaxBytes` | `int` / 24 MB | Bitmap VRAM budget |
| | `rasterizeItems` | `bool` / true | Bake messages into GPU bitmaps |
| | `textCacheMaxSize` | `int` / 1000 | Paragraph/layout cache size |
| | `effectInterceptors` | `List<BarrageEffectInterceptor>` / [] | Custom text-effect pipeline |

</details>

### BarrageType

| Value | Behavior |
| --- | --- |
| `scroll` | Enters from the right edge, scrolls left until off-screen |
| `topFixed` | Pinned to a lane at the top for `fixedDuration` |
| `bottomFixed` | Pinned to a lane at the bottom for `fixedDuration` |

### Emoji & Sprite System

```dart
final atlas = EmojiAtlas.instance;

// 1. Register emoji metadata (one image can serve several trigger keys)
atlas.registerAll([
  EmojiInfo(
    id: '29',
    asset: 'assets/emoji/29.png',
    keys: ['[laugh]', '[happy]'],
    sourceType: EmojiSourceType.asset,   // asset | atlas | network | animated
    width: 24,
    height: 24,
  ),
]);

// 2. Preload images (async; resolves sprites/animations internally)
await atlas.preloadAll();

// 3. Atlas-sliced emoji: register source rects before loading the sheet image
atlas.updateAtlasRects({
  '[sliced-a]': const Rect.fromLTWH(0, 0, 96, 96),
  '[sliced-b]': const Rect.fromLTWH(96, 0, 96, 96),
});
```

| Class | Key members | Purpose |
| --- | --- | --- |
| `EmojiAtlas` | `register`, `registerAll`, `updateAtlasRects`, `preloadEmoji`, `preloadAll`, `find`, `image`, `getStaticSprite`, `getAnimation`, `resolveLoadedImage`, `regex`, `clear` | Registry mapping trigger keys to images/sprites/animations; builds a match-all `RegExp` over the keys |
| `EmojiInfo` | `id`, `asset`, `keys`, `sourceType`, `width`, `height` | One emoji's metadata |
| `EmojiSourceType` | `asset` / `atlas` / `network` / `animated` | How the asset is interpreted (animated source types build a `SpriteAnimation` from a horizontal strip) |
| `AtlasLoader` | `loadFromAsset(path, {targetWidth, targetHeight})` | Decode a Flutter asset into a `ui.Image` |
| `SpriteSheet` | `getSpriteRect(i)`, `generateAllRects()`, `srcWidth`, `srcHeight` | Grid math for slicing a sheet |

The parser splits message content on the atlas regex: plain runs become `TextFragment`, registered keys become `SpriteFragment` (atlas source) or `EmojiFragment` (everything else), so text and graphics mix freely in one message.

### Interaction

```dart
FlameBarrageWidget(
  controller: controller,
  config: config,
  emojiAtlas: EmojiAtlas.instance,
  enablePointerEvents: true, // required for direct hit testing
);

controller.send(BarrageItem(
  content: 'Tap me!',
  onTapDown: () => debugPrint('down'),
  onTapUp: () => debugPrint('up'),
  onLongTapDown: () => debugPrint('long-press'),
  onTapCancel: () => debugPrint('cancel'),
));

// Custom gesture layer (e.g. a video player keeps swipes):
final handled = controller.triggerItemAt(x, y, longPress: false);
```

Hit testing runs back-to-front over the live entry list; messages without callbacks never claim the gesture.

#### Tap-to-hold (action sheet flow)

A common product flow: tap a message to freeze it, present block/report/like actions, then release it to continue scrolling. The engine holds the message in place — it neither scrolls nor expires while held:

```dart
final item = controller.pauseItemAt(x, y);   // null when nothing was hit
if (item != null) {
  final action = await showActionSheet(item.userId, item.content);
  // ... block the user, file a report, or like ...
}
controller.resumeAllPaused();                // held messages continue from the spot they froze at
```

| Member | Description |
| --- | --- |
| `controller.pauseItemAt(x, y)` | Holds the top-most message at the point; returns it (or null on a miss). Held messages keep their position and lane |
| `controller.resumeAllPaused()` | Releases every held message |
| `controller.pausedCount` | How many messages are currently held |

### Extending Rendering

**`BarrageEffectInterceptor`** — intercept matching messages and substitute a custom `LayoutSpan`:

```dart
class VipRainbowInterceptor extends BarrageEffectInterceptor {
  const VipRainbowInterceptor();

  @override
  bool shouldIntercept(BarrageItem item, BarrageConfig config) =>
      item.content.contains('[VIP]');

  @override
  LayoutSpan createCustomSpan({
    required BarrageItem item,
    required String text,
    required ui.Paragraph paragraph,
    required double x, required double y,
    required double width, required double height,
    required BarrageConfig config,
  }) {
    return VipRainbowTextLayoutSpan(
      x: x, y: y, width: width, height: height,
      text: text, paragraph: paragraph, config: config,
    );
  }
}

class VipRainbowTextLayoutSpan extends TextLayoutSpan {
  const VipRainbowTextLayoutSpan({
    required super.x, required super.y, required super.width,
    required super.height, required super.text, required super.paragraph,
    required this.config,
  });

  final BarrageConfig config;

  // Subclasses of TextLayoutSpan should implement copyWithY(double) so
  // vertical centering can reposition them.
  VipRainbowTextLayoutSpan copyWithY(double newY) => VipRainbowTextLayoutSpan(
    x: x, y: newY, width: width, height: height,
    text: text, paragraph: paragraph, config: config,
  );

  @override
  void paint(ui.Canvas canvas) {
    // gradient fill, outline, badges — anything a Canvas can draw
  }
}

// Wire it up:
final config = BarrageConfig(effectInterceptors: [const VipRainbowInterceptor()]);
```

**`Fragment`** — the content unit produced by parsing (`TextFragment`, `SpriteFragment`, `EmojiFragment`). You can extend it and feed your own parsing path before layout.

**`LayoutSpan`** — the paint unit inside a `LayoutResult`. Built-ins: `TextLayoutSpan` (fill + optional stroke paragraph), `EmojiLayoutSpan` (image), `SpriteLayoutSpan` (atlas sprite with optional `SpriteAnimationPlayer`).

**`BarrageMotionEffect`** — choreographed mount effects. Implement `duration`, `onSpawn`, `advance`, and optionally `paint` (drawn underneath the text bitmap). The engine owns spawning, per-frame advance, lane reservation and particle rendering (`BarrageFxParticleSystem`); you only write pose fields (`x/y/alpha/rotation/scale`) into the provided `BarrageFxState` each frame. See the bundled effects (`HorseRidingEffect`, `RocketLaunchEffect`, …) as references.

### Data Protocols

```dart
final message = const MessageProtocol().fromWebSocketJson(json);   // BarrageItem? from {content, type, vip}
final emojis = const EmojiProtocol().parseRegistryJson(rawList);    // List<EmojiInfo> from {id, keys, asset, width, height}
```

### Utilities

| Class | Members | Purpose |
| --- | --- | --- |
| `FpsMonitor` | `start(callback)`, `stop()` | Real display-frame FPS sampling over a sliding window |
| `Measure` | `Measure.profile(label, action)` | Times a closure, warns above 1 ms |
| `ColorUtil` | `fromHex`, `fromInt`, `toARGB32` | Color conversions |
| `BarrageLogger` | `d/w/e` | Tagged logging used across the engine |

### Advanced Internals

Exported for custom hosting or experimentation:

| Area | Classes |
| --- | --- |
| Systems | `BarrageDataSystem`, `BarrageMotionSystem`, `BarrageMetricsSystem`, `BarrageRenderSystem` |
| Shared state | `BarrageContext` (config, clock, viewport, lanes, caches, live entries) |
| Scheduler | `TrackManager` (lane lifecycle), `TrackAllocator` (lane picking), `SpeedStrategy` (catch-up-safe speeds) |
| Caches | `RenderCache`/`CachedRender` (ref-counted bitmaps), `TextCache` (paragraphs), `PictureCache` (legacy), `AtlasCache`, `SpriteCache`, `PicturePool` |
| Pools | `BarragePool` (entries), `ObjectPool<T>` (generic `Poolable` pooling) |
| Render | `BaseRenderer`, `MixedRenderer` (picture recording), `EmojiRenderer` |
| Model | `BarrageEntry` (pooled runtime state), `BarrageTrack`, `BarrageMessage` |
| Clock | `EngineClock` (`now()` ms, `nowPrecise()` sub-ms, `scale` for playback rate) |
| Effects | `GlowEffect`, `GradientEffect`, `ShadowEffect`, `StrokeEffect` (paint factories), `ComboAnimation`, `SpriteAnimationPlayer` |

---

## 📺 TV & Low-End Device Tuning

| Setting | Recommendation | Why |
| --- | --- | --- |
| `fps` | Set it to the panel's refresh rate (60 or 120) | The engine can never step more often than the display refreshes. Setting `fps: 144` on a 60 Hz TV changes nothing — if frames still drop, the cost per frame is the problem, not the target rate. |
| `rasterizeItems` | `true` (default) | Removes per-frame text, stroke and shadow rasterization. |
| `maxVisibleCount` | 40–80 on a weak GPU | This is the number of bitmap blits per frame. |
| `showStroke` | Keep `true` if the text sits on bright video; disable if the bake cost itself shows up as a startup spike | The outline is rasterized once per message rather than per frame. |
| `trackHeight` / `area` | A full screen of lanes only helps if the GPU can fill it | Fewer lanes means fewer messages on screen at once. |
| `pictureCacheMaxSize` / `rasterCacheMaxBytes` | Fit the bitmap budget to the device | Caps the GPU memory the cache may hold (`rasterCacheBytes` reports live usage). |
| `emitInterval` | `0.1` for a calm stream, `0.02`–`0.05` for a busy one | Paces how many new messages are shaped and baked per second. Set `realtimeMode: true` instead when latency matters more than density. |

Calling `controller.clear()` (or disposing `FlameBarrageWidget`) stops the game loop entirely, so a paused room costs nothing.

---

## 🔬 Performance Philosophy

1. **Minimize allocations** — pooled entries, reused paints, zero-allocation steady-state loops
2. **Reduce framework overhead** — no widgets per message, one flat render pass
3. **Maximize GPU utilization** — baked bitmaps, one textured quad per message
4. **Rasterize each message once, not every frame**
5. **Integrate motion with real elapsed time** — velocity never depends on frame load

---

## 📋 License

Released under the MIT License.
