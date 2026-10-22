import 'nrktv_dates.dart';

final _numberPrefix = RegExp(r'^\s*(\d{1,4})\.\s+(.+)$', dotAll: true);
final _relativeDay = RegExp(
  r'^(i dag|i går|i morgen|mandag|tirsdag|onsdag|torsdag|fredag|lørdag|søndag)(?:\s*·\s*(.+))?$',
  caseSensitive: false,
  unicode: true,
);

/// The "3." in front of "3. Title", unless it is a day of the month ("16. oktober ...").
({int number, String rest})? nrkNumberPrefix(String title) {
  final match = _numberPrefix.firstMatch(title);
  if (match == null || nrkStartsWithMonth(match.group(2)!)) return null;
  return (number: int.parse(match.group(1)!), rest: match.group(2)!.trim());
}

/// An episode title without the counter NRK puts in front of it.
///
/// The prefix is dropped only when it is [number], the episode's own number: "2. verdenskrig" stays whole.
/// An episode called just "episode" reads "Episode 3".
String nrkEpisodeTitle(String raw, {required int? number}) {
  final title = raw.trim();
  final prefix = nrkNumberPrefix(title);
  if (number == null || prefix == null || prefix.number != number) return title;
  if (prefix.rest.toLowerCase() == 'episode') return 'Episode $number';
  return prefix.rest;
}

/// A news title with a relative day ("I går · Headline", "Tirsdag · Headline") restated with the real date.
///
/// NRK rewrites those words as days pass, so the same edition would carry different names over a week.
String nrkNewsTitle(String raw, ({int year, int month, int day})? date) {
  final title = raw.trim();
  final match = _relativeDay.firstMatch(title);
  if (match == null || date == null) return title;
  final day = '${date.day}. ${nrkMonthName(date.month)}';
  final headline = match.group(2);
  return headline == null ? day : '$day · $headline';
}

/// NRK separates lines with a bare carriage return.
String nrkPlainText(String raw) => raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
