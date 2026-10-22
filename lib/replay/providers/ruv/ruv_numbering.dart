import 'ruv_dates.dart';

// RÚV has no seasons. A sequel is a separate programme whose title says which one it is ("Kappsmál II",
// "Molang IV", "Flækjur 3", "Fleiri pabbahelgar"), and episodes carry a number that is only sometimes usable.

final _titleEpisode = RegExp(r'^\s*Þáttur\s+(\d{1,4})\b', caseSensitive: false, unicode: true);
final _roman = RegExp(r'^[IVX]+$');
final _small = RegExp(r'^\d{1,2}$');

const _romanValues = {'I': 1, 'V': 5, 'X': 10};

/// The season a programme stands for, read from its title, or null when the title says nothing.
///
/// A roman numeral or a one or two digit number after the last space counts; four digits are a year and do not.
/// "Rás 2" and "Rásar 2" are radio stations, not a second season.
int? ruvSeasonNumber(String programmeTitle) {
  final words = programmeTitle.trim().split(RegExp(r'\s+'));
  if (words.length < 2) return null;
  final last = words.last;
  final before = words[words.length - 2];
  if (_roman.hasMatch(last)) return _fromRoman(last);
  if (_small.hasMatch(last)) {
    if (before.startsWith('Rás')) return null;
    final value = int.parse(last);
    return value > 0 ? value : null;
  }
  // "Fleiri" means "more": the follow-up programme of a series.
  return words.first == 'Fleiri' ? 2 : null;
}

/// Value of a well-formed roman numeral up to XX, or null.
int? _fromRoman(String numeral) {
  var total = 0;
  for (var i = 0; i < numeral.length; i++) {
    final value = _romanValues[numeral[i]]!;
    final next = i + 1 < numeral.length ? _romanValues[numeral[i + 1]]! : 0;
    total += value < next ? -value : value;
  }
  return total >= 1 && total <= 20 && _toRoman(total) == numeral ? total : null;
}

String _toRoman(int value) {
  const steps = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
  var rest = value;
  final out = StringBuffer();
  for (final (size, letters) in steps) {
    while (rest >= size) {
      out.write(letters);
      rest -= size;
    }
  }
  return out.toString();
}

/// The number an episode states: its `number`, else the one in a title such as "Þáttur 3 af 6".
int? ruvStatedEpisodeNumber(Map<String, dynamic> episode) {
  final number = episode['number'];
  if (number is num && number > 0) return number.toInt();
  final match = _titleEpisode.firstMatch(episode['title'] as String? ?? '');
  return match == null ? null : int.parse(match.group(1)!);
}

typedef RuvNumberedEpisode = ({Map<String, dynamic> episode, int number});

/// Numbers the episodes of one programme and returns them in ascending order.
///
/// Stated numbers are used when every episode has one and no two share it. Daily programmes reuse numbers (the
/// evening news restarts its count each week), so those are numbered by first broadcast instead, oldest first.
List<RuvNumberedEpisode> ruvNumberEpisodes(List<Map<String, dynamic>> episodes) {
  final stated = [for (final e in episodes) ruvStatedEpisodeNumber(e)];
  final usable = !stated.contains(null) && stated.toSet().length == stated.length;
  final numbers = usable ? stated.cast<int>() : _byAirDate(episodes);
  final numbered = [for (var i = 0; i < episodes.length; i++) (episode: episodes[i], number: numbers[i])];
  numbered.sort((a, b) => a.number.compareTo(b.number));
  return numbered;
}

List<int> _byAirDate(List<Map<String, dynamic>> episodes) {
  final order = List<int>.generate(episodes.length, (i) => i);
  order.sort((a, b) {
    final left = ruvDateTime(episodes[a]['firstrun']);
    final right = ruvDateTime(episodes[b]['firstrun']);
    if (left != null && right != null) {
      final byDate = left.compareTo(right);
      if (byDate != 0) return byDate;
    }
    return a.compareTo(b);
  });
  final numbers = List<int>.filled(episodes.length, 0);
  for (var rank = 0; rank < order.length; rank++) {
    numbers[order[rank]] = rank + 1;
  }
  return numbers;
}
