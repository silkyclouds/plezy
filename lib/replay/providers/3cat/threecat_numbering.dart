/// A video title split into the numbers it carries and what is left of it.
class ThreeCatNumbering {
  final int? season;
  final int? episode;
  final String title;

  const ThreeCatNumbering({this.season, this.episode, required this.title});
}

final _numbered = RegExp(r'^T(\d+)\s*x\s*C(\d+)\s*(?:[-:]\s*(.*))?$', caseSensitive: false);
final _date = RegExp(r'\b\d{1,2}/\d{1,2}/\d{4}\b');

/// 3Cat prints the season and episode in the title, `T2xC5 - Name`, even for shows whose data has no season field.
ThreeCatNumbering threeCatNumbering(String raw) {
  final text = raw.trim();
  final match = _numbered.firstMatch(text);
  if (match == null) return ThreeCatNumbering(title: text);
  final rest = (match.group(3) ?? '').trim();
  return ThreeCatNumbering(
    season: int.parse(match.group(1)!),
    episode: int.parse(match.group(2)!),
    title: rest.isEmpty ? text : rest,
  );
}

bool threeCatHasDate(String text) => _date.hasMatch(text);

bool threeCatIsOnlyDate(String text) => RegExp(r'^\s*\d{1,2}/\d{1,2}/\d{4}\s*$').hasMatch(text);

/// The season an item belongs to: the broadcaster's own season id (`PUTEMP_2`), else `T<n>` read from the title.
/// Null for items outside any season.
String? threeCatSeasonKey(Map<String, dynamic> item) {
  final own = _ownSeason(item);
  if (own != null) return own['id'] as String;
  final season = threeCatNumbering(item['titol'] as String? ?? '').season;
  return season == null ? null : 'T$season';
}

/// The season number a key stands for, when it has one.
int? threeCatSeasonNumber(String key) {
  final match = RegExp(r'(\d+)$').firstMatch(key);
  return match == null ? null : int.parse(match.group(1)!);
}

/// The broadcaster's name for the season ("2a Temporada"), when it gave one.
String? threeCatSeasonLabel(Map<String, dynamic> item) {
  final label = _ownSeason(item)?['desc'];
  return label is String && label.trim().isNotEmpty ? label.trim() : null;
}

Map<String, dynamic>? _ownSeason(Map<String, dynamic> item) {
  final seasons = item['temporades'];
  if (seasons is! List) return null;
  final maps = seasons.whereType<Map<String, dynamic>>().where((s) => s['id'] is String).toList();
  if (maps.isEmpty) return null;
  return maps.where((s) => s['main'] == true).firstOrNull ?? maps.first;
}
