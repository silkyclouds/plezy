/// A video title split into what the app shows as text and as numbers.
typedef ArdEpisodeTitle = ({String title, int? season, int? episode});

// "(S03/E01)", the label ARD appends to numbered episodes. It is the only place the numbers appear.
final _label = RegExp(r'\s*\(?\bS(\d{1,3})\s*/\s*E(\d{1,4})\b\)?', caseSensitive: false);
// "Folge 29: " or "Folge 29 - ", the running number in front of the title.
final _runningNumber = RegExp(r'^\s*Folge\s+(\d{1,5})\s*[:\-–]\s*', caseSensitive: false);

/// Reads season and episode numbers out of [raw] and returns the title without them.
///
/// With a "(S03/E01)" label both numbers are taken from it and the "Folge 29:" prefix is dropped, because the
/// numbers are shown separately. Without the label, a "Folge 29:" prefix gives an episode number alone and
/// stays in the title.
ArdEpisodeTitle ardEpisodeTitle(String raw) {
  final label = _label.allMatches(raw).lastOrNull;
  if (label != null) {
    final cleaned = _tidy(raw.replaceRange(label.start, label.end, ''));
    final withoutPrefix = _tidy(cleaned.replaceFirst(_runningNumber, ''));
    return (
      title: withoutPrefix.isEmpty ? cleaned : withoutPrefix,
      season: int.parse(label.group(1)!),
      episode: int.parse(label.group(2)!),
    );
  }
  final running = _runningNumber.firstMatch(raw);
  return (title: _tidy(raw), season: null, episode: running == null ? null : int.parse(running.group(1)!));
}

/// Splits "Show | Tagline" at the first bar. The tagline is null when there is none.
({String title, String? subtitle}) ardSplitTitle(String text) {
  final cut = text.indexOf(' | ');
  if (cut < 0) return (title: _tidy(text), subtitle: null);
  final subtitle = _tidy(text.substring(cut + 3));
  return (title: _tidy(text.substring(0, cut)), subtitle: subtitle.isEmpty ? null : subtitle);
}

String _tidy(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
