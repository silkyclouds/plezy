import 'nrktv_dates.dart';
import 'nrktv_text.dart';

typedef NrkNumberedEpisode = ({Map<String, dynamic> episode, int number});

/// The number NRK states for an episode: `sequenceNumber`, else the counter in front of its title.
int? nrkStatedNumber(Map<String, dynamic> episode) {
  final sequence = (episode['sequenceNumber'] as num?)?.toInt();
  if (sequence != null && sequence > 0) return sequence;
  final title = (episode['titles'] as Map?)?['title'];
  return title is String ? nrkNumberPrefix(title)?.number : null;
}

/// Numbers the episodes of ONE season and returns them in viewing order.
///
/// Stated numbers are used when every episode has one and no two agree. Standard and news series state none, and a
/// season with gaps or repeats cannot be trusted either, so those are numbered by release date, oldest first.
/// NRK lists newest first, so of two episodes released at the same moment the later in the list is the older.
List<NrkNumberedEpisode> nrkNumberEpisodes(List<Map<String, dynamic>> episodes) {
  final stated = [for (final e in episodes) nrkStatedNumber(e)];
  final usable = !stated.contains(null) && stated.toSet().length == stated.length;
  final numbers = usable ? stated.cast<int>() : _byReleaseDate(episodes);
  final numbered = [for (var i = 0; i < episodes.length; i++) (episode: episodes[i], number: numbers[i])];
  numbered.sort((a, b) => a.number.compareTo(b.number));
  return numbered;
}

List<int> _byReleaseDate(List<Map<String, dynamic>> episodes) {
  final order = List<int>.generate(episodes.length, (i) => i);
  order.sort((a, b) {
    final left = nrkParseDate(episodes[a]['releaseDateOnDemand']);
    final right = nrkParseDate(episodes[b]['releaseDateOnDemand']);
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

/// Season numbers from season names. Sequential series name them "1", "2"; standard series use the year ("2022")
/// and news series the month ("202610"), which are numbers too and sort the right way. Any other naming gets the
/// position in the list.
List<int> nrkSeasonNumbers(List<String> names) {
  final parsed = [for (final n in names) int.tryParse(n)];
  if (!parsed.contains(null) && parsed.toSet().length == parsed.length) return parsed.cast<int>();
  return [for (var i = 0; i < names.length; i++) i + 1];
}
