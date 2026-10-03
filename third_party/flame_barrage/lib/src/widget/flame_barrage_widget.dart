import 'package:flame/game.dart';
import '../atlas/emoji_atlas.dart';
import '../core/barrage_config.dart';
import '../core/barrage_engine.dart';
import 'package:flutter/material.dart';
import '../core/barrage_controller.dart';

class FlameBarrageWidget extends StatefulWidget {
  const FlameBarrageWidget({
    super.key,
    required this.config,
    required this.emojiAtlas,
    required this.controller,
    this.enablePointerEvents = false,
  });

  final BarrageConfig config;
  final EmojiAtlas emojiAtlas;
  final BarrageController controller;
  final bool enablePointerEvents;
  @override
  State<FlameBarrageWidget> createState() => _FlameBarrageWidgetState();
}

class _FlameBarrageWidgetState extends State<FlameBarrageWidget> {
  late final BarrageEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = BarrageEngine(config: widget.config, emojiAtlas: widget.emojiAtlas);
    widget.controller.attach(_engine);
  }

  @override
  void didUpdateWidget(covariant FlameBarrageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _engine.updateConfig(widget.config);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach(_engine);
      widget.controller.attach(_engine);
    }
  }

  @override
  void dispose() {
    // Stop the display ticker and release native Pictures/Paragraphs before the
    // surrounding route finishes its transition. Waiting for GC/onRemove made
    // repeated room and PiP transitions look like an ever-growing Windows heap.
    _engine.clear();
    widget.controller.detach(_engine);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ClipRect(
      clipBehavior: Clip.hardEdge,
      // This canvas renders/interacts with danmaku, not a keyboard-driven game.
      // Flame otherwise autofocuses and handles every key before the room's
      // Escape/media shortcuts can see it. IgnorePointer does not exclude focus.
      // ExcludeFocus also prevents Tab/click-driven focus after reparenting,
      // without disabling danmaku pointer callbacks.
      child: ExcludeFocus(child: GameWidget(game: _engine, autofocus: false)),
    );

    if (!widget.enablePointerEvents) {
      child = IgnorePointer(child: child);
    }

    return child;
  }
}
