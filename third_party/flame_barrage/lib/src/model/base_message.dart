import 'package:flame_barrage/flame_barrage.dart';

class BarrageMessage {
  const BarrageMessage({
    required this.id,
    required this.content,
    required this.timestamp,
    this.type = BarrageType.scroll,
    this.userId,
    this.userName,
    this.priority = 0,
  });

  /// Stable message identifier assigned by the host application.
  final String id;

  /// Raw text displayed on screen.
  final String content;

  /// Wall-clock time the message was produced at the source.
  final DateTime timestamp;

  /// Placement/scroll behavior of the message.
  final BarrageType type;

  /// Optional sender identifier, useful for deduplication and moderation.
  final String? userId;

  /// Optional display name shown alongside the message.
  final String? userName;

  /// Higher-priority messages win lane allocation when tracks are contested.
  final int priority;
}
