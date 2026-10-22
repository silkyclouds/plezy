/// Season and episode position of an item, as far as the broadcaster says or implies.
typedef DrtvNumbers = ({int? season, int? episode});

final _tag = RegExp(r'S(\d{1,4}):E(\d{1,5})');
final _extraDetails = RegExp(r'S[ÆE]SON\s+(\d{1,4})(?:\s+EPISODE\s+(\d{1,5}))?', caseSensitive: false, unicode: true);
final _ordinalContext = RegExp(r'^\s*(\d{1,5})\.\s*(?:episode|afsnit)', caseSensitive: false);
final _numberedName = RegExp(r'(?<!\p{L})(?:episode|afsnit|del)\s+(\d{1,4})\s*$', caseSensitive: false, unicode: true);

/// Reads the numbers of an episode or season item.
///
/// The structured fields win. Long-running shows use the year as season number and DR keeps that convention in its own
/// labels ("S2026:E14"), so the labels are read next, then the ordinal in the contextual title ("20. episode") and a
/// trailing "Episode 3" in the name. A zero is a placeholder, not a number.
DrtvNumbers drtvNumbers(Map<String, dynamic> item) {
  var season = _positive(item['seasonNumber']);
  var episode = _positive(item['episodeNumber']);
  final custom = item['customFields'];
  final fields = custom is Map<String, dynamic> ? custom : const <String, dynamic>{};

  final tag = _tag.firstMatch('${fields['PlayButtonExtraDetails'] ?? ''}');
  if (tag != null) {
    season ??= _positive(tag.group(1));
    episode ??= _positive(tag.group(2));
  }
  final extra = _extraDetails.firstMatch('${fields['ExtraDetails'] ?? ''}');
  if (extra != null) {
    season ??= _positive(extra.group(1));
    episode ??= _positive(extra.group(2));
  }
  episode ??= _positive(_ordinalContext.firstMatch('${item['contextualTitle'] ?? ''}')?.group(1));
  episode ??= _positive(_numberedName.firstMatch('${item['episodeName'] ?? item['title'] ?? ''}')?.group(1));
  return (season: season, episode: episode);
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

/// An episode's own name and, when it can be told, the show it belongs to.
typedef DrtvEpisodeName = ({String name, String? show});

final _ordinalPrefix = RegExp(r'^\d{1,5}\.\s+(.+)$');
final _ordinalOnly = RegExp(r'^\d{1,5}\.\s*(?:episode|afsnit)$', caseSensitive: false);

/// Strips the "Show: " prefix DR puts in front of episode names.
///
/// With [showTitle] known the prefix is removed directly. Without it, the contextual title (the name alone, sometimes
/// led by its ordinal, "3. Name") shows where the prefix ends. A name that is only the show's title falls back to the
/// contextual title, such as "20. episode".
DrtvEpisodeName drtvEpisodeName(Map<String, dynamic> item, {String? showTitle}) {
  final raw = ((item['episodeName'] as String?) ?? (item['title'] as String?) ?? '').trim();
  final context = ((item['contextualTitle'] as String?) ?? '').trim();

  if (showTitle != null && raw.startsWith('$showTitle: ') && raw.length > showTitle.length + 2) {
    return (name: raw.substring(showTitle.length + 2).trim(), show: showTitle);
  }
  final withoutOrdinal = _ordinalPrefix.firstMatch(context)?.group(1);
  for (final tail in [context, ?withoutOrdinal]) {
    if (tail.isNotEmpty && raw.endsWith(': $tail')) {
      return (name: tail, show: showTitle ?? raw.substring(0, raw.length - tail.length - 2).trim());
    }
  }
  final numberOnly = _ordinalOnly.hasMatch(context);
  if (numberOnly && (raw == showTitle || (showTitle == null && !raw.contains(': ') && !_numberedName.hasMatch(raw)))) {
    return (name: context, show: showTitle ?? raw);
  }
  return (name: raw.isEmpty ? context : raw, show: showTitle);
}
