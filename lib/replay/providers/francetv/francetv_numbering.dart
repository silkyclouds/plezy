/// Season and episode position of a video, as far as the broadcaster says or implies.
typedef FranceTvNumbers = ({int? season, int? episode});

final _seasonEpisodeTag = RegExp(r'^\s*S(\d{1,3})\s*E(\d{1,5})\b', caseSensitive: false);
final _episodeAfterWord = RegExp(
  r'(?<!\p{L})(?:épisode|episode|ép\.|ep\.)\s*(\d{1,4})\b',
  caseSensitive: false,
  unicode: true,
);
final _episodeBeforeWord = RegExp(
  r'(?<![\p{L}\d])(\d{1,4})\s*(?:ème|eme|e|è|ère|ere|er)?\s+(?:épisode|episode)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);
final _seasonWord = RegExp(r'(?<!\p{L})(?:saison|season)\s*(\d{1,3})\b', caseSensitive: false, unicode: true);

/// Reads the numbers of one video item.
///
/// The structured `season` and `episode` fields win. Otherwise the `S8 E2038 - Title` prefix of
/// `episode_title` is read, then the title itself ("Épisode 3", "3ème épisode", "Saison 2"), because
/// some programmes carry their order only in the text. A zero is a placeholder, not a number.
FranceTvNumbers franceTvNumbers(Map<String, dynamic> item) {
  var season = _positive(item['season']);
  var episode = _positive(item['episode']);
  if (season != null && episode != null) return (season: season, episode: episode);

  final tag = _seasonEpisodeTag.firstMatch(item['episode_title'] as String? ?? '');
  if (tag != null) {
    season ??= int.tryParse(tag.group(1)!);
    episode ??= int.tryParse(tag.group(2)!);
  }
  final title = item['title'] as String? ?? '';
  episode ??= _firstNumber(title, [_episodeAfterWord, _episodeBeforeWord]);
  season ??= _firstNumber(title, [_seasonWord]);
  return (season: _positive(season), episode: _positive(episode));
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

int? _firstNumber(String text, List<RegExp> patterns) {
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return int.tryParse(match.group(1)!);
  }
  return null;
}
