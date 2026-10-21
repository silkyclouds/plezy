/// What Auvio's free text says about where an episode sits in its show.
///
/// The catalogue has no season or episode fields: the season is a `Sxx` suffix of the title and the
/// episode a leading `NN - ` of the subtitle, or a subtitle that reads `Episode N`.
class RtbfNumbering {
  /// The title without its season suffix and with single spaces.
  final String showTitle;
  final int? season;
  final int? episode;

  /// The subtitle without its episode number, or the whole title when there is no subtitle.
  final String episodeTitle;

  const RtbfNumbering({required this.showTitle, required this.episodeTitle, this.season, this.episode});

  bool get isNumbered => season != null || episode != null;
}

final _seasonSuffix = RegExp(r'^(.*?)\s+S(\d{1,3})$', caseSensitive: false);
final _episodePrefix = RegExp(r'^(\d{1,3})\s*[-–]\s*(.+)$');
final _episodeWord = RegExp(r'^[ÉE]pisode\s+(\d{1,3})\b', caseSensitive: false);

RtbfNumbering rtbfParseNumbering({required String? title, required String? subtitle}) {
  final cleanTitle = _squeeze(title);
  final seasonMatch = _seasonSuffix.firstMatch(cleanTitle);
  final showTitle = seasonMatch == null ? cleanTitle : seasonMatch.group(1)!.trim();
  final season = seasonMatch == null ? null : int.parse(seasonMatch.group(2)!);

  final cleanSubtitle = _squeeze(subtitle);
  final episodeMatch = _episodePrefix.firstMatch(cleanSubtitle);
  if (episodeMatch != null) {
    return RtbfNumbering(
      showTitle: showTitle,
      season: season,
      episode: int.parse(episodeMatch.group(1)!),
      episodeTitle: episodeMatch.group(2)!.trim(),
    );
  }
  return RtbfNumbering(
    showTitle: showTitle,
    season: season,
    episode: int.tryParse(_episodeWord.firstMatch(cleanSubtitle)?.group(1) ?? ''),
    episodeTitle: cleanSubtitle.isEmpty ? cleanTitle : cleanSubtitle,
  );
}

String _squeeze(String? text) => (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
