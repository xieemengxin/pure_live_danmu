/// Matches chat text against the viewer's shield entries.
///
/// A plain entry blocks every message that contains it, ignoring case. An
/// entry written as `/body/` is a regular expression, matched case-sensitively:
/// that is how Simple Live writes them, so a list imported from it keeps
/// working. A pattern that does not compile is ignored.
class DanmakuShieldMatcher {
  DanmakuShieldMatcher(Iterable<String> entries) {
    final keywords = <String>[];
    final patterns = <RegExp>[];
    for (final entry in entries) {
      final text = entry.trim();
      if (text.isEmpty) continue;
      final body = patternBodyOf(text);
      if (body == null) {
        keywords.add(text.toLowerCase());
        continue;
      }
      try {
        patterns.add(RegExp(body));
      } on FormatException {
        // 写错的正则当作不存在，别让一条坏规则挡住其它规则。
      }
    }
    _keywords = List<String>.unmodifiable(keywords);
    _patterns = List<RegExp>.unmodifiable(patterns);
  }

  static final DanmakuShieldMatcher none = DanmakuShieldMatcher(const <String>[]);

  late final List<String> _keywords;
  late final List<RegExp> _patterns;

  /// The expression inside `/.../`, or null when [entry] is a plain keyword.
  static String? patternBodyOf(String entry) {
    if (entry.length <= 2 || !entry.startsWith('/') || !entry.endsWith('/')) return null;
    return entry.substring(1, entry.length - 1);
  }

  bool matches(String text) {
    if (_keywords.isNotEmpty) {
      final lowered = text.toLowerCase();
      if (_keywords.any(lowered.contains)) return true;
    }
    return _patterns.any((pattern) => pattern.hasMatch(text));
  }
}
