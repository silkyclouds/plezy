/// ERR numbers most episodes itself. When it sends 0, the number is often still written in the title, as "5. osa",
/// "Osa 5" or "Episode 5" (and "серия 5" on the Russian site).
final _episodePatterns = [
  RegExp(r'(\d{1,4})\s*\.\s*osa\b', caseSensitive: false),
  RegExp(r'\bosa\s+(\d{1,4})\b', caseSensitive: false),
  RegExp(r'\bepisode\s+(\d{1,4})\b', caseSensitive: false),
  RegExp(r'серия\s+(\d{1,4})', caseSensitive: false),
  RegExp(r'(\d{1,4})\s*-?\s*я\s+серия', caseSensitive: false),
];

final _seasonPatterns = [
  RegExp(r'(\d{1,2})\s*\.\s*hooaeg\b', caseSensitive: false),
  RegExp(r'\bhooaeg\s+(\d{1,2})\b', caseSensitive: false),
  RegExp(r'\bseason\s+(\d{1,2})\b', caseSensitive: false),
  RegExp(r'сезон\s+(\d{1,2})', caseSensitive: false),
];

/// The episode number written in [heading] or [subHeading], or null.
int? errEpisodeFromTitle(String? heading, String? subHeading) => _firstMatch(_episodePatterns, [subHeading, heading]);

/// The season number written in [heading] or [subHeading], or null.
int? errSeasonFromTitle(String? heading, String? subHeading) => _firstMatch(_seasonPatterns, [subHeading, heading]);

int? _firstMatch(List<RegExp> patterns, List<String?> texts) {
  for (final text in texts) {
    if (text == null) continue;
    for (final pattern in patterns) {
      final value = int.tryParse(pattern.firstMatch(text)?.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
  }
  return null;
}
