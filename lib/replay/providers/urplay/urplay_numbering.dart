/// UR names seasons only in prose: a description starting "Säsong 2." and the labels of a programme page.
final _seasonPrefix = RegExp(r'^\s*Säsong\s+(\d+)\s*[.:]?\s*', caseSensitive: false);

/// The season a series description announces, or null when it announces none.
int? urSeasonFromDescription(String? description) {
  final match = description == null ? null : _seasonPrefix.firstMatch(description);
  return match == null ? null : int.parse(match.group(1)!);
}

/// The description without its leading "Säsong N." marker.
String urStripSeasonPrefix(String description) => description.replaceFirst(_seasonPrefix, '').trim();

/// Season and episode numbers from the labels of a programme page, such as `["Säsong 5", "Avsnitt 2", "15 min"]`.
({int? season, int? episode}) urNumbersFromLabels(Object? labels) {
  int? season;
  int? episode;
  if (labels is List) {
    for (final label in labels.whereType<String>()) {
      final match = RegExp(r'^(Säsong|Avsnitt)\s+(\d+)$').firstMatch(label.trim());
      if (match == null) continue;
      final number = int.parse(match.group(2)!);
      if (match.group(1) == 'Säsong') {
        season = number;
      } else {
        episode = number;
      }
    }
  }
  return (season: season, episode: episode);
}

/// Key under which two series count as seasons of one show: same title up to case and spacing.
String urTitleKey(String title) => title.replaceAll(RegExp(r'[\s ]+'), ' ').trim().toLowerCase();
