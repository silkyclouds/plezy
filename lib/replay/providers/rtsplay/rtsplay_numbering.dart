/// Season and episode position of a video, as far as the broadcaster says or implies.
typedef RtsNumbers = ({int? season, int? episode});

// "(Episode 4 - Saison 15)", the label RTS appends to the title of numbered series.
final _episodeThenSeason = RegExp(
  r'[ée]pisode\s+(\d{1,4})\s*[-–—,/]\s*saison\s+(\d{1,3})',
  caseSensitive: false,
  unicode: true,
);
final _seasonThenEpisode = RegExp(
  r'saison\s+(\d{1,3})\s*[-–—,:]?\s*[ée]pisode\s+(\d{1,4})',
  caseSensitive: false,
  unicode: true,
);
final _tag = RegExp(r'(?<![A-Za-z0-9])S(\d{1,3})\s?E(\d{1,4})(?![A-Za-z0-9])', caseSensitive: false);
final _episodeOnly = RegExp(r'\(\s*[ée]pisode\s+(\d{1,4})\s*\)', caseSensitive: false, unicode: true);

final _label = RegExp(
  r'\s*\(\s*[ée]pisode\s+\d{1,4}(?:\s*[-–—,/]\s*saison\s+\d{1,3})?\s*\)\s*$',
  caseSensitive: false,
  unicode: true,
);

/// Reads the numbers of one video item.
///
/// The structured `episode.seasonNumber` and `episode.number` win. Otherwise the numbers are read from the
/// title, where RTS writes them as "(Episode 4 - Saison 15)" or just "(Episode 4)". A part counter such
/// as "3/3" is not read: magazines use it for parts of one broadcast, not for episodes of a series.
RtsNumbers rtsNumbers(Map<String, dynamic> item) {
  final episode = item['episode'];
  var season = _positive(episode is Map ? episode['seasonNumber'] : null);
  var number = _positive(episode is Map ? episode['number'] : null);
  if (season != null && number != null) return (season: season, episode: number);

  final text = [item['title'], if (episode is Map) episode['title']].whereType<String>().join(' ');
  final derived = _fromText(text);
  season ??= derived.season;
  number ??= derived.episode;
  return (season: season, episode: number);
}

/// The title without its "(Episode N - Saison M)" label, which the app shows as numbers instead.
String rtsCleanTitle(String title) {
  final cleaned = title.replaceFirst(_label, '').trim();
  return cleaned.isEmpty ? title.trim() : cleaned;
}

RtsNumbers _fromText(String text) {
  final both = _episodeThenSeason.firstMatch(text);
  if (both != null) return (season: int.parse(both.group(2)!), episode: int.parse(both.group(1)!));
  final reversed = _seasonThenEpisode.firstMatch(text);
  if (reversed != null) return (season: int.parse(reversed.group(1)!), episode: int.parse(reversed.group(2)!));
  final tag = _tag.firstMatch(text);
  if (tag != null) return (season: int.parse(tag.group(1)!), episode: int.parse(tag.group(2)!));
  final only = _episodeOnly.firstMatch(text);
  return (season: null, episode: only == null ? null : int.parse(only.group(1)!));
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}
