/// A bare number, not the start of a date (`20/10/26`), a time or a decimal.
const _number = r'(\d{1,4})(?!\d|[/\-.:]\d)';

final _labelled = RegExp(
  r'\b(?:episodio|capítulo|capitulo|cap\.|programa|entrega|ep\.)\s*(?:n[ºo°.]?\s*)?' + _number,
  caseSensitive: false,
  unicode: true,
);
final _seasonEpisode = RegExp(r'\bT\d{1,2}\s*[-–x]?\s*E(?:p\.?)?\s*' + _number, caseSensitive: false);
final _seasonLabel = RegExp(r'(?:\btemporada\s+|\bT)(\d{1,2})\b', caseSensitive: false);

/// The number of an episode within its season. RTVE states it in `episode` for drama and children's series; talk
/// shows, quiz shows and magazines leave it at 0 and only say it in the title ("Programa 232").
int? rtveEpisodeNumber(Map<String, dynamic> video) {
  final stated = (video['episode'] as num?)?.toInt();
  if (stated != null && stated > 0) return stated;
  for (final key in ['longTitle', 'title', 'shortTitle']) {
    final title = video[key];
    if (title is! String) continue;
    final number = _fromTitle(title);
    if (number != null) return number;
  }
  return null;
}

/// The season of an episode: the order RTVE gives its season, else the "T3" or "Temporada 3" in its titles.
int? rtveSeasonNumber(Map<String, dynamic> video) {
  final order = (video['temporadaOrden'] as num?)?.toInt();
  if (order != null && order > 0) return order;
  for (final key in ['temporada', 'longTitle', 'title']) {
    final text = video[key];
    if (text is! String) continue;
    final match = _seasonLabel.firstMatch(text);
    if (match != null) return int.parse(match.group(1)!);
  }
  return null;
}

int? _fromTitle(String title) {
  final both = _seasonEpisode.firstMatch(title);
  if (both != null) return _positive(both.group(1)!);
  final labelled = _labelled.firstMatch(title);
  return labelled == null ? null : _positive(labelled.group(1)!);
}

int? _positive(String digits) {
  final value = int.parse(digits);
  return value > 0 ? value : null;
}
