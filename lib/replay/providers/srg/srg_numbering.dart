/// Season and episode position of a video, as far as the broadcaster says or implies.
typedef SrgNumbers = ({int? season, int? episode});

/// Reads season and episode numbers from an item and cleans the label out of its title.
///
/// The structured `episode.seasonNumber` and `episode.number` win. Otherwise the numbers come from the
/// title, where each broadcaster writes them in its own words, for instance "(Episode 4 - Saison 15)" or
/// "(Staffel 4, Folge 4)". A part counter such as "3/3" is never read: magazines use it for parts of one
/// broadcast, not for episodes of a series.
class SrgNumbering {
  static final _tag = RegExp(r'(?<![A-Za-z0-9])S(\d{1,3})\s?E(\d{1,4})(?![A-Za-z0-9])', caseSensitive: false);

  final RegExp _episodeThenSeason;
  final RegExp _seasonThenEpisode;
  final RegExp _episodeOnly;
  final RegExp _label;
  final RegExp? _leading;

  /// [episode] and [season] are regular-expression alternatives for the words the broadcaster uses, such as
  /// `episodio|ep\.?`. With [leadingLabel], a title that starts with "Ep. 3 - " carries the number too.
  SrgNumbering({required String episode, required String season, bool leadingLabel = false})
    : _episodeThenSeason = _rx('(?<!\\p{L})(?:$episode)\\s*(\\d{1,4})\\s*[-–—,/]\\s*(?:$season)\\s*(\\d{1,3})'),
      _seasonThenEpisode = _rx('(?<!\\p{L})(?:$season)\\s*(\\d{1,3})\\s*[-–—,:]?\\s*(?:$episode)\\s*(\\d{1,4})'),
      _episodeOnly = _rx('\\(\\s*(?:$episode)\\s*(\\d{1,4})\\s*\\)'),
      _label = _rx(
        '\\s*\\(\\s*(?:(?:$episode)\\s*\\d{1,4}(?:\\s*[-–—,/]\\s*(?:$season)\\s*\\d{1,3})?'
        '|(?:$season)\\s*\\d{1,3}\\s*[-–—,:]?\\s*(?:$episode)\\s*\\d{1,4})\\s*\\)\\s*\$',
      ),
      _leading = leadingLabel ? _rx('^\\s*(?:$episode)\\s*(\\d{1,4})\\s*[-–—:]\\s*(?=\\S)') : null;

  SrgNumbers numbers(Map<String, dynamic> item) {
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

  /// The title without its numbering label, which the app shows as numbers instead.
  String cleanTitle(String title) {
    var cleaned = title.replaceFirst(_label, '').trim();
    final leading = _leading;
    if (leading != null) {
      final match = leading.firstMatch(cleaned);
      if (match != null) cleaned = cleaned.substring(match.end).trim();
    }
    return cleaned.isEmpty ? title.trim() : cleaned;
  }

  SrgNumbers _fromText(String text) {
    final both = _episodeThenSeason.firstMatch(text);
    if (both != null) return (season: int.parse(both.group(2)!), episode: int.parse(both.group(1)!));
    final reversed = _seasonThenEpisode.firstMatch(text);
    if (reversed != null) return (season: int.parse(reversed.group(1)!), episode: int.parse(reversed.group(2)!));
    final tag = _tag.firstMatch(text);
    if (tag != null) return (season: int.parse(tag.group(1)!), episode: int.parse(tag.group(2)!));
    final only = _episodeOnly.firstMatch(text) ?? _leading?.firstMatch(text);
    return (season: null, episode: only == null ? null : int.parse(only.group(1)!));
  }
}

RegExp _rx(String pattern) => RegExp(pattern, caseSensitive: false, unicode: true);

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}
