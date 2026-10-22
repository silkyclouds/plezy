/// An episode's own name and its position, read from the "3/26 Name" form the broadcaster puts in titles.
typedef CeskaTelevizeEpisodeName = ({String name, int? number});

final _counter = RegExp(r'^(\d{1,4})/(\d{1,4})(?:\s+(.+))?$');

/// Splits a leading "N/M" counter off an episode title. A counter whose N exceeds M is a date, not a position.
CeskaTelevizeEpisodeName ceskatelevizeEpisodeName(String title) {
  final match = _counter.firstMatch(title);
  if (match == null) return (name: title, number: null);
  final number = int.parse(match.group(1)!);
  final total = int.parse(match.group(2)!);
  if (number < 1 || number > total) return (name: title, number: null);
  return (name: match.group(3)?.trim() ?? title, number: number);
}

typedef CeskaTelevizeSeasonEntry = ({String id, String title});

final _numeralFirst = RegExp(r'^\s*(\d{1,3}|[IVXLC]{1,8})\s*\.?\s*(?:[řŘ]ada|[sS][ée]rie|[sS]ez[oó]na)');
final _numeralLast = RegExp(r'^\s*(?:[řŘ]ada|[sS][ée]rie|[sS]ez[oó]na)\s+(\d{1,3}|[IVXLC]{1,8})\s*$');

/// One season number per entry, in the same order.
///
/// The broadcaster gives no integer: "II. řada" carries a Roman numeral and extras such as "Osudy" or a `group:`
/// entry carry none. Numbered entries keep their number; the others continue after the highest one, in list order, so
/// every season of a show has its own number.
List<int> ceskatelevizeSeasonNumbers(List<CeskaTelevizeSeasonEntry> seasons) {
  final parsed = [for (final s in seasons) s.id.startsWith('group:') ? null : _numberOf(s.title)];
  final taken = <int>{};
  final numbers = <int?>[
    for (final n in parsed)
      if (n != null && taken.add(n)) n else null,
  ];
  var next = taken.fold<int>(0, (a, b) => a > b ? a : b);
  return [for (final n in numbers) n ?? ++next];
}

int? _numberOf(String title) {
  final raw = (_numeralFirst.firstMatch(title) ?? _numeralLast.firstMatch(title))?.group(1);
  if (raw == null) return null;
  final number = int.tryParse(raw) ?? _roman(raw);
  return number != null && number > 0 ? number : null;
}

int? _roman(String numeral) {
  const values = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100};
  var total = 0;
  for (var i = 0; i < numeral.length; i++) {
    final value = values[numeral[i]];
    if (value == null) return null;
    final following = i + 1 < numeral.length ? values[numeral[i + 1]] ?? 0 : 0;
    total += value < following ? -value : value;
  }
  return total;
}
