/// A show name split into the name proper and the series number it carries.
class StvrShowName {
  final String base;
  final int? season;

  const StvrShowName(this.base, this.season);

  /// Two names of one show compare equal under this key whatever their case or spacing.
  String get key => base.toLowerCase();
}

final _spaces = RegExp(r'\s+');
final _romanTail = RegExp(r'^(.*\S)\s+([IVXL]+)$');
final _wordTail = RegExp(r'^(.*\S)\s+(\d{1,2})\.\s*séria$', caseSensitive: false, unicode: true);
final _dangling = RegExp(r'[\s\-–:,]+$');
final _partAfterNumber = RegExp(
  r'(?:^|[\s(\-–:])(\d{1,4})\.\s*(?:časť|diel|epizóda)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);
final _partBeforeNumber = RegExp(r'^(?:epizóda|časť|diel)\s+(\d{1,4})(?!\d)', caseSensitive: false, unicode: true);

const _romanValues = [(50, 'L'), (40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
const _maxRoman = 39;

/// Collapses the double and trailing spaces the broadcaster leaves in names.
String stvrTidy(String text) => text.trim().replaceAll(_spaces, ' ');

/// Splits "Detektívi zo severu XII" into the base name and series 12. STVR publishes each series of a programme as its
/// own show with the Roman numeral in the name; names without a numeral keep a null season.
StvrShowName stvrParseShowName(String name) {
  final tidy = stvrTidy(name);
  final roman = _romanTail.firstMatch(tidy);
  if (roman != null) {
    final number = _romanToInt(roman.group(2)!);
    final base = _clean(roman.group(1)!);
    if (number != null && base.isNotEmpty) return StvrShowName(base, number);
  }
  final word = _wordTail.firstMatch(tidy);
  if (word != null) {
    final base = _clean(word.group(1)!);
    if (base.isNotEmpty) return StvrShowName(base, int.parse(word.group(2)!));
  }
  return StvrShowName(tidy, null);
}

String _clean(String base) => base.replaceFirst(_dangling, '');

int? _romanToInt(String numeral) {
  var total = 0;
  for (var i = 0; i < numeral.length; i++) {
    final value = _digitValue(numeral[i]);
    final next = i + 1 < numeral.length ? _digitValue(numeral[i + 1]) : 0;
    total += value < next ? -value : value;
  }
  if (total < 1 || total > _maxRoman) return null;
  return _intToRoman(total) == numeral ? total : null;
}

int _digitValue(String letter) => _romanValues.firstWhere((v) => v.$2 == letter).$1;

String _intToRoman(int number) {
  var rest = number;
  final out = StringBuffer();
  for (final (value, letters) in _romanValues) {
    while (rest >= value) {
      out.write(letters);
      rest -= value;
    }
  }
  return out.toString();
}

/// The part number a subtitle states ("Briga - 2. časť", "Epizóda 4"), or null.
int? stvrStatedEpisodeNumber(String subtitle) {
  final match = _partAfterNumber.firstMatch(subtitle) ?? _partBeforeNumber.firstMatch(subtitle);
  return match == null ? null : int.parse(match.group(1)!);
}

/// Numbers the recordings of one series, given their subtitles oldest first and the series' [total] recording count.
///
/// Numbers stated by every subtitle win when they are all different. Otherwise a recording is numbered by its place in
/// the series' air order, counted from the oldest, so a list cut short at the old end still numbers the rest correctly.
List<int> stvrEpisodeNumbers(List<String> subtitlesOldestFirst, {required int total}) {
  final stated = [for (final s in subtitlesOldestFirst) stvrStatedEpisodeNumber(s)];
  final complete = stated.every((n) => n != null) && stated.toSet().length == stated.length;
  if (complete && stated.isNotEmpty) return [for (final n in stated) n!];
  final first = (total - subtitlesOldestFirst.length).clamp(0, total) + 1;
  return [for (var i = 0; i < subtitlesOldestFirst.length; i++) first + i];
}
