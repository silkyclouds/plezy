final _episodeWord = RegExp(
  r'(?<!\p{L})(?:[ée]pisode|[ée]p)\.?\s*(?:n°\s*|no\.?\s*|#\s*)?(\d{1,3})(?!\d)',
  caseSensitive: false,
  unicode: true,
);
final _seasonWord = RegExp(r'(?<!\p{L})saison\s+(\d{1,4})(?!\d)', caseSensitive: false, unicode: true);

/// The number in "Episode 12", "Ep. 3" or "episode n° 4", or null when the title carries none.
///
/// The stations broadcast dated editions, so most titles give no number and the air date orders them.
int? deriveEpisodeNumber(String title) {
  final match = _episodeWord.firstMatch(title);
  return match == null ? null : int.parse(match.group(1)!);
}

/// The number of a season label such as "Saison 2024", or [fallback] when it has none.
int seasonNumberFromLabel(String label, {required int fallback}) {
  final match = _seasonWord.firstMatch(label);
  return match == null ? fallback : int.parse(match.group(1)!);
}
