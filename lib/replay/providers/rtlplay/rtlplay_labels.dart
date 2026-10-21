/// A display label `{label, accessibilityLabel}` of a teaser or programme page. The catalogue states durations,
/// dates and season counts only as French text, so the helpers below read them back.
typedef RtlPlayLabel = ({String text, String? kind});

List<RtlPlayLabel> rtlPlayLabels(Object? raw) => [
  if (raw is List)
    for (final item in raw.whereType<Map<String, dynamic>>())
      if (item['label'] is String) (text: item['label'] as String, kind: item['accessibilityLabel'] as String?),
];

String? labelOfKind(List<RtlPlayLabel> labels, String kind) =>
    labels.where((l) => l.kind == kind).map((l) => l.text).firstOrNull;

int? yearOf(List<RtlPlayLabel> labels) => int.tryParse(labelOfKind(labels, 'Année de production') ?? '');

/// "93 min" or "1 h 20 min" in seconds, null for anything else.
int? durationOf(List<RtlPlayLabel> labels) {
  final text = labelOfKind(labels, 'Durée');
  if (text == null) return null;
  final hours = int.tryParse(RegExp(r'(\d+)\s*h').firstMatch(text)?.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(RegExp(r'(\d+)\s*min').firstMatch(text)?.group(1) ?? '');
  if (minutes == null && hours == 0) return null;
  return (hours * 60 + (minutes ?? 0)) * 60;
}

/// Season count from "1 saison" or "5 saisons".
int? seasonCountOf(List<RtlPlayLabel> labels) {
  for (final l in labels) {
    final n = RegExp(r'^(\d+)\s+saisons?$').firstMatch(l.text.trim())?.group(1);
    if (n != null) return int.parse(n);
  }
  return null;
}

/// The label the broadcaster highlights, such as "Nouvel épisode chaque dimanche".
String? emphasizedLabel(Object? raw) {
  if (raw is! List) return null;
  for (final item in raw.whereType<Map<String, dynamic>>()) {
    if (item['emphasized'] == true && item['label'] is String) return item['label'] as String;
  }
  return null;
}

const _months = {
  'janv': 1,
  'févr': 2,
  'mars': 3,
  'avr': 4,
  'mai': 5,
  'juin': 6,
  'juil': 7,
  'août': 8,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'déc': 12,
};

/// "mar. 20 oct. 2026" as a UTC date; null when the text is not in that shape.
DateTime? frenchDateOf(String? text) {
  if (text == null) return null;
  final match = RegExp(r'(\d{1,2})\s+([^\s.\d]+)\.?\s+(\d{4})').firstMatch(text.toLowerCase());
  if (match == null) return null;
  final token = match.group(2)!;
  final month = _months.entries.where((e) => token.startsWith(e.key)).map((e) => e.value).firstOrNull;
  if (month == null) return null;
  return DateTime.utc(int.parse(match.group(3)!), month, int.parse(match.group(1)!));
}

/// "20/10/2026" at the end of a broadcast title, as a UTC date.
DateTime? slashDateOf(String title) {
  final match = RegExp(r'\((\d{2})/(\d{2})/(\d{4})\)\s*$').firstMatch(title);
  if (match == null) return null;
  return DateTime.tryParse('${match.group(3)}-${match.group(2)}-${match.group(1)}T00:00:00Z');
}

/// Episode titles come numbered ("3. Persuasion"); the number is shown separately.
String stripEpisodePrefix(String title) => title.replaceFirst(RegExp(r'^\d+\.\s+'), '').trim();

/// "PG_12" as "12+"; other codes are not known well enough to show.
String? ratingOf(Object? icons) {
  if (icons is! List) return null;
  for (final code in icons.whereType<String>()) {
    final age = RegExp(r'^PG_(\d+)$').firstMatch(code)?.group(1);
    if (age != null) return '$age+';
  }
  return null;
}

/// Sort key that ignores case and French accents, so "Éclats" files under E.
String sortKey(String title) {
  const from = 'àâäçéèêëîïôöùûüÿœ';
  const to = 'aaaceeeeiioouuuyo';
  final buffer = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at < 0 ? char : to[at]);
  }
  return buffer.toString();
}
