import 'lrt_feed.dart';
import 'lrt_models.dart';

typedef LrtNumberedRecording = ({LrtRecording recording, int? number});

// "102 dalis", "3 d.", "12 serija", "1d" and the ordinal "2-oji dalis": the count comes before the word.
final _numberBeforeWord = RegExp(
  r'(?<![\d.])(\d{1,3})\s*(?:-?\s*(?:oji|asis))?\s*(?:dalis|dalies|d\.|d\b|serija|laida|epizodas|ser\.)',
  caseSensitive: false,
  unicode: true,
);
// "Serija 5", "Dalis 7", "Epizodas 4" and "Nr. 12".
final _numberAfterWord = RegExp(
  r'(?:dalis|serija|laida|epizodas|nr\.)\s*(\d{1,3})\b',
  caseSensitive: false,
  unicode: true,
);
// "I d.", "IV dalis".
final _romanBeforeWord = RegExp(r'\b([IVXL]{1,5})\s*(?:dalis|d\.)', unicode: true);
final _yearTitle = RegExp(r'^(\d{4})(?:-(\d+))?$');

/// The number a recording's title states ("Pažvelk į profesiją kitaip. 102 dalis"), or null.
int? lrtEpisodeNumberFromTitle(String title) {
  final plain = _numberBeforeWord.firstMatch(title) ?? _numberAfterWord.firstMatch(title);
  if (plain != null) return _positive(int.parse(plain.group(1)!));
  final roman = _romanBeforeWord.firstMatch(title)?.group(1);
  return roman == null ? null : _positive(_fromRoman(roman));
}

/// Orders one season's recordings oldest first and numbers them.
///
/// Numbers stated in titles are used when every recording has one and no two agree. Otherwise recordings are numbered
/// by broadcast date, but only when [complete]: a feed cut at [lrtFeedLimit] misses the oldest ones, so a rank in it
/// would be wrong and the number stays null.
List<LrtNumberedRecording> lrtNumberRecordings(List<LrtRecording> newestFirst, {required bool complete}) {
  final stated = [for (final r in newestFirst) lrtEpisodeNumberFromTitle(r.title)];
  final usable = stated.isNotEmpty && !stated.contains(null) && stated.toSet().length == stated.length;
  final order = _oldestFirst(newestFirst);
  if (usable) {
    final byNumber = [for (final i in order) (recording: newestFirst[i], number: stated[i])];
    byNumber.sort((a, b) => a.number!.compareTo(b.number!));
    return byNumber;
  }
  return [
    for (var rank = 0; rank < order.length; rank++)
      (recording: newestFirst[order[rank]], number: complete ? rank + 1 : null),
  ];
}

/// Seasons oldest first. Titles that are years (`2024`, `2024-2`) sort by year then by suffix; anything else keeps the
/// site's order reversed, since the site lists newest first.
List<LrtSeason> lrtOrderSeasons(List<LrtSeason> newestFirst) {
  final keys = [for (final s in newestFirst) _yearKey(s.title)];
  if (keys.isNotEmpty && !keys.contains(null)) {
    final indexed = List<int>.generate(newestFirst.length, (i) => i);
    indexed.sort((a, b) {
      final left = keys[a]!;
      final right = keys[b]!;
      return left.$1 != right.$1 ? left.$1.compareTo(right.$1) : left.$2.compareTo(right.$2);
    });
    return [for (final i in indexed) newestFirst[i]];
  }
  return newestFirst.reversed.toList();
}

/// The year a season title names, or null.
int? lrtSeasonYear(String title) => _yearKey(title)?.$1;

(int, int)? _yearKey(String title) {
  final match = _yearTitle.firstMatch(title.trim());
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.tryParse(match.group(2) ?? '') ?? 1);
}

/// Indexes of [newestFirst] from oldest to newest. Equal dates keep feed order reversed, so a day's recordings
/// read in the order they were published.
List<int> _oldestFirst(List<LrtRecording> newestFirst) {
  final order = List<int>.generate(newestFirst.length, (i) => i);
  order.sort((a, b) {
    final left = newestFirst[a].published;
    final right = newestFirst[b].published;
    if (left != null && right != null) {
      final byDate = left.compareTo(right);
      if (byDate != 0) return byDate;
    }
    return b.compareTo(a);
  });
  return order;
}

int? _positive(int? value) => value != null && value > 0 ? value : null;

int? _fromRoman(String text) {
  const values = {'I': 1, 'V': 5, 'X': 10, 'L': 50};
  var total = 0;
  for (var i = 0; i < text.length; i++) {
    final value = values[text[i]]!;
    final next = i + 1 < text.length ? values[text[i + 1]]! : 0;
    total += value < next ? -value : value;
  }
  return total;
}
