/// Season, episode and display title of a video, taken from its metadata or, failing that, from its title.
class M6plusEpisodeInfo {
  final int? season;
  final int? episode;
  final String title;

  const M6plusEpisodeInfo({required this.season, required this.episode, required this.title});
}

final _codePrefix = RegExp(r'^S(\d+)\s*E(\d+)\s*(?:[-–:]\s*)?(.*)$', caseSensitive: false, dotAll: true);
final _wordedEpisode = RegExp(r'(?:épisode|episode|émission|emission)\s+(\d+)', caseSensitive: false, unicode: true);
final _seasonWord = RegExp(r'saison\s+(\d+)', caseSensitive: false);

/// Reads numbers from [season] and [episode] when the broadcaster gave them, else from "S3 E4 - ..." and
/// "Épisode 4" in [title]. A title that is only a code is replaced by "Épisode N".
M6plusEpisodeInfo m6plusEpisodeInfo({required String title, int? season, int? episode, String? seasonTitle}) {
  final trimmed = title.trim();
  final code = _codePrefix.firstMatch(trimmed);
  final rest = code?.group(3)?.trim();

  final resolvedSeason = season ?? _int(code?.group(1)) ?? _int(_seasonWord.firstMatch(seasonTitle ?? '')?.group(1));
  final resolvedEpisode = episode ?? _int(code?.group(2)) ?? _int(_wordedEpisode.firstMatch(trimmed)?.group(1));

  var display = code == null ? trimmed : rest ?? '';
  if (display.isEmpty) {
    display = resolvedEpisode == null ? trimmed : 'Épisode $resolvedEpisode';
  }
  return M6plusEpisodeInfo(season: resolvedSeason, episode: resolvedEpisode, title: display);
}

int? _int(String? value) => value == null ? null : int.tryParse(value);
