typedef BbcNumberedEpisode = ({Map<String, dynamic> item, int number});

/// Key of the season group an episode belongs to.
///
/// iPlayer has no season object. Episodes of most shows carry a `slice_id` such as `m002csng-structural-2-m0030pxs`;
/// shows without one only state the series in the subtitle (`Series 1: 3. Title`); the rest fall into one group.
String bbcSliceKey(Map<String, dynamic> episode) {
  final slice = episode['slice_id'];
  if (slice is String && slice.isNotEmpty) {
    final brand = episode['tleo_id'];
    return brand is String && slice.startsWith('$brand-') ? slice.substring(brand.length + 1) : slice;
  }
  final label = _SubtitleLabel.of(episode['subtitle']);
  if (label.series == null) return bbcAllKey;
  return label.extras ? 'series-${label.series}-extras' : 'series-${label.series}';
}

const bbcAllKey = 'all';

/// The series number a subtitle states (`Series 2: Episode 6`), or null.
int? bbcSeriesNumber(Object? subtitle) {
  final label = _SubtitleLabel.of(subtitle);
  return label.extras ? null : label.series;
}

class _SubtitleLabel {
  static final _pattern = RegExp(r'^Series (\d+)( Extras)?:');

  final int? series;
  final bool extras;

  const _SubtitleLabel(this.series, this.extras);

  factory _SubtitleLabel.of(Object? subtitle) {
    final match = subtitle is String ? _pattern.firstMatch(subtitle) : null;
    if (match == null) return const _SubtitleLabel(null, false);
    return _SubtitleLabel(int.parse(match.group(1)!), match.group(2) != null);
  }
}

/// One season of a show: a real series, an editorial collection, or the extras.
class BbcSeasonGroup {
  final String key;
  final String title;
  final int number;
  final List<BbcNumberedEpisode> episodes;

  const BbcSeasonGroup({required this.key, required this.title, required this.number, required this.episodes});
}

enum _Kind { series, collection, extras, all }

class _Slice {
  final String key;
  final _Kind kind;
  final String title;
  final int? seriesNumber;
  final int position;
  final List<Map<String, dynamic>> items;

  const _Slice(this.key, this.kind, this.title, this.seriesNumber, this.position, this.items);
}

/// Splits the episodes of a show into seasons: real series first by number, then editorial collections in the
/// order iPlayer gives them, then extras. Editorial slices (`manual-`) are not series, so they become seasons of
/// their own rather than being merged into one.
List<BbcSeasonGroup> bbcSeasonGroups(List<Map<String, dynamic>> episodes, {required String showTitle}) {
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final item in episodes) {
    byKey.putIfAbsent(bbcSliceKey(item), () => []).add(item);
  }
  final slices = [
    for (final (index, entry) in byKey.entries.indexed)
      _describe(entry.key, entry.value, _position(entry.key, index), showTitle),
  ];
  final series = slices.where((s) => s.kind == _Kind.series).toList()
    ..sort((a, b) => a.seriesNumber!.compareTo(b.seriesNumber!));
  final others = slices.where((s) => s.kind == _Kind.collection || s.kind == _Kind.all).toList()..sort(_byPosition);
  final extras = slices.where((s) => s.kind == _Kind.extras).toList()..sort(_byPosition);

  var next = series.isEmpty ? 1 : series.last.seriesNumber! + 1;
  var extraNumber = 0;
  return [
    for (final s in series) _group(s, s.seriesNumber!),
    for (final s in others) _group(s, s.kind == _Kind.all ? 1 : next++),
    for (final s in extras) _group(s, extraNumber++ == 0 ? 0 : next++),
  ];
}

int _byPosition(_Slice a, _Slice b) => a.position.compareTo(b.position);

/// The order iPlayer numbers a slice in (`manual-4-dances` is the fourth), else where the slice first appeared.
int _position(String key, int appearance) {
  final match = RegExp(r'^(?:structural|manual)-(\d+)-').firstMatch(key);
  return match == null ? appearance : int.parse(match.group(1)!);
}

BbcSeasonGroup _group(_Slice slice, int number) =>
    BbcSeasonGroup(key: slice.key, title: slice.title, number: number, episodes: bbcNumberEpisodes(slice.items));

_Slice _describe(String key, List<Map<String, dynamic>> items, int position, String showTitle) {
  if (key == bbcAllKey) return _Slice(key, _Kind.all, showTitle, null, position, items);

  final structural = RegExp(r'^structural-(\d+)-(.+)$').firstMatch(key);
  final manual = RegExp(r'^manual-\d+-(.+)$').firstMatch(key);
  final subtitled = RegExp(r'^series-(\d+)(-extras)?$').firstMatch(key);
  final stated = bbcSeriesNumber(items.first['subtitle']);

  if (structural != null) {
    if (structural.group(2) == 'extras') return _Slice(key, _Kind.extras, 'Extras', null, position, items);
    final number = stated ?? int.parse(structural.group(1)!);
    return _Slice(key, _Kind.series, 'Series $number', number, position, items);
  }
  if (subtitled != null) {
    final number = int.parse(subtitled.group(1)!);
    if (subtitled.group(2) != null) return _Slice(key, _Kind.extras, 'Series $number Extras', null, position, items);
    return _Slice(key, _Kind.series, 'Series $number', number, position, items);
  }
  if (manual != null && stated != null) {
    return _Slice(key, _Kind.series, 'Series $stated', stated, position, items);
  }
  final tail = manual?.group(1) ?? key;
  return _Slice(key, _Kind.collection, _humanise(tail), null, position, items);
}

String _humanise(String tail) {
  final words = tail.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return words.isEmpty ? tail : words[0].toUpperCase() + words.substring(1);
}

/// Numbers the episodes of one season in viewing order.
///
/// The stated position is used when every episode has one and no two agree. Dated and current-affairs shows state
/// none, so those are numbered by release date, oldest first.
List<BbcNumberedEpisode> bbcNumberEpisodes(List<Map<String, dynamic>> items) {
  final stated = [for (final item in items) (item['parent_position'] as num?)?.toInt()];
  final usable = !stated.contains(null) && stated.toSet().length == stated.length;
  final order = List<int>.generate(items.length, (i) => i)..sort((a, b) => _compare(items, stated, usable, a, b));
  return [for (final (rank, index) in order.indexed) (item: items[index], number: usable ? stated[index]! : rank + 1)];
}

int _compare(List<Map<String, dynamic>> items, List<int?> stated, bool usable, int a, int b) {
  if (usable) return stated[a]!.compareTo(stated[b]!);
  final left = _released(items[a]);
  final right = _released(items[b]);
  if (left != null && right != null) {
    final byDate = left.compareTo(right);
    if (byDate != 0) return byDate;
  }
  return b.compareTo(a);
}

DateTime? _released(Map<String, dynamic> item) {
  final raw = item['release_date_time'];
  return raw is String ? DateTime.tryParse(raw) : null;
}
