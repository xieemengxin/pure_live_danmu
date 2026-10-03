/// Why a [LiveDanmakuSender] cannot post right now.
enum LiveDanmakuSendBlock {
  /// The platform needs an account session and none is stored.
  loginRequired,
}

/// Thrown by [LiveDanmakuSender.sendMessage]; [message] is shown to the viewer.
class LiveDanmakuSendException implements Exception {
  const LiveDanmakuSendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Implemented by a `LiveDanmaku` engine whose platform lets the signed-in
/// viewer post chat messages into the room it is connected to.
abstract interface class LiveDanmakuSender {
  /// Null when a message can be posted, otherwise what is missing.
  LiveDanmakuSendBlock? get sendBlock;

  /// Longest message the platform accepts, in characters.
  int get maxSendLength;

  /// Posts [text] to the room as the signed-in viewer.
  ///
  /// Throws [LiveDanmakuSendException] when the message does not go out or the
  /// platform rejects it.
  Future<void> sendMessage(String text);
}
