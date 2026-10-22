import 'svtplay_dates.dart';

typedef SvtNumberedEpisode = ({Map<String, dynamic> episode, int number});

final _positionLabel = RegExp(r'avsnitt\s+(\d{1,4})', caseSensitive: false, unicode: true);
final _titlePrefix = RegExp(r'^\s*(\d{1,4})\.\s+');
final _seasonLabel = RegExp(r'(?:säsong|season)\s+(\d{1,3})', caseSensitive: false, unicode: true);

/// The episode's number as the catalogue states it or implies it, or null.
///
/// `number` wins. Otherwise the display position ("Svenska - Avsnitt 3") or a "3. " prefix of the title is read.
int? svtEpisodeNumber(Map<String, dynamic> episode) {
  final number = _positive(episode['number']);
  if (number != null) return number;
  final position = _positionLabel.firstMatch(episode['positionInSeason'] as String? ?? '');
  if (position != null) return int.parse(position.group(1)!);
  final prefix = _titlePrefix.firstMatch(episode['name'] as String? ?? '');
  return prefix == null ? null : int.parse(prefix.group(1)!);
}

/// The episode's own title, without the "3. " counter the catalogue puts in front of `name`.
String svtEpisodeTitle(Map<String, dynamic> episode) {
  final raw = (episode['nameRaw'] as String?)?.trim() ?? '';
  if (raw.isNotEmpty) return raw;
  final name = (episode['name'] as String?)?.trim() ?? '';
  final stripped = name.replaceFirst(_titlePrefix, '').trim();
  return stripped.isEmpty ? name : stripped;
}

/// Numbers every episode of one season, in ascending order.
///
/// Stated numbers are used when they are all present and distinct. A season where they are not (missing, or two
/// episodes sharing a number) is numbered by broadcast date instead, so the order is still the viewing order.
List<SvtNumberedEpisode> svtNumberEpisodes(List<Map<String, dynamic>> episodes) {
  final stated = [for (final e in episodes) svtEpisodeNumber(e)];
  final usable = !stated.contains(null) && stated.toSet().length == stated.length;
  final numbers = usable ? stated.cast<int>() : _byAirDate(episodes);
  final numbered = [for (var i = 0; i < episodes.length; i++) (episode: episodes[i], number: numbers[i])];
  numbered.sort((a, b) => a.number.compareTo(b.number));
  return numbered;
}

/// Numbers seasons given newest first, as the catalogue lists them.
///
/// A season's `number` is used when all are positive and distinct, then a "Säsong 3" in its name. A show whose
/// seasons are single production periods, or that has one unnumbered season, gets 1..n from the oldest.
List<int> svtSeasonNumbers(List<Map<String, dynamic>> seasons) {
  for (final read in [_stated, _fromName]) {
    final numbers = [for (final s in seasons) read(s)];
    if (!numbers.contains(null) && numbers.toSet().length == numbers.length) return numbers.cast<int>();
  }
  return [for (var i = 0; i < seasons.length; i++) seasons.length - i];
}

int? _stated(Map<String, dynamic> season) => _positive(season['number']);

int? _fromName(Map<String, dynamic> season) {
  final match = _seasonLabel.firstMatch(season['name'] as String? ?? '');
  return match == null ? null : int.parse(match.group(1)!);
}

List<int> _byAirDate(List<Map<String, dynamic>> episodes) {
  final order = List<int>.generate(episodes.length, (i) => i);
  order.sort((a, b) {
    final left = svtDate(episodes[a]['validFrom']);
    final right = svtDate(episodes[b]['validFrom']);
    if (left != null && right != null) {
      final byDate = left.compareTo(right);
      if (byDate != 0) return byDate;
    }
    return b.compareTo(a);
  });
  final numbers = List<int>.filled(episodes.length, 0);
  for (var rank = 0; rank < order.length; rank++) {
    numbers[order[rank]] = rank + 1;
  }
  return numbers;
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}
