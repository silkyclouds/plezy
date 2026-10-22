/// NHK numbers nothing: a season is the calendar year of the first broadcast, and an episode number comes from the
/// last three digits of its id when those are trustworthy, else from the order of broadcast inside the year.
final _officialId = RegExp(r'^(\d{4})(\d{3})$');

DateTime? nhkParseDate(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

/// When the item first aired, or failing that when it went online.
DateTime? nhkAirDate(Map<String, dynamic> item) =>
    nhkParseDate(item['first_broadcasted_at']) ?? nhkParseDate((item['video'] as Map?)?['published_at']);

/// Year of the season an item belongs to; [now] covers an item with no date at all.
int nhkSeasonYear(Map<String, dynamic> item, DateTime now) => (nhkAirDate(item) ?? now).year;

/// The running number NHK puts in the id (`5107009` is number 9 of programme `5107`), or null when the id has no
/// such shape or the number is zero.
int? nhkOfficialNumber(String id) {
  final number = int.tryParse(_officialId.firstMatch(id)?.group(2) ?? '');
  return number == null || number == 0 ? null : number;
}

/// An episode of one season with the number it is shown under.
typedef NhkNumbered = ({Map<String, dynamic> item, int number});

/// Orders and numbers the episodes of ONE season.
///
/// Ids of one programme come in several families (`2032xxx` and `5107xxx` are both Japanology Plus), and numbers of
/// different families do not follow broadcast order. Official numbers are used only when every episode of the season
/// has one, all from one family, all different; otherwise episodes are numbered 1..n by broadcast date.
List<NhkNumbered> nhkNumberSeason(List<Map<String, dynamic>> episodes) {
  final byDate = [...episodes]..sort(_byAirDateThenId);
  if (_hasUsableOfficialNumbers(episodes)) {
    final byNumber = [...episodes]
      ..sort((a, b) => nhkOfficialNumber(a['id'] as String)!.compareTo(nhkOfficialNumber(b['id'] as String)!));
    return [for (final item in byNumber) (item: item, number: nhkOfficialNumber(item['id'] as String)!)];
  }
  return [for (var i = 0; i < byDate.length; i++) (item: byDate[i], number: i + 1)];
}

bool _hasUsableOfficialNumbers(List<Map<String, dynamic>> episodes) {
  final ids = [for (final e in episodes) e['id'] as String];
  if (ids.any((id) => nhkOfficialNumber(id) == null)) return false;
  final families = {for (final id in ids) id.substring(0, 4)};
  final numbers = {for (final id in ids) nhkOfficialNumber(id)};
  return families.length == 1 && numbers.length == ids.length;
}

int _byAirDateThenId(Map<String, dynamic> a, Map<String, dynamic> b) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final byDate = (nhkAirDate(a) ?? epoch).compareTo(nhkAirDate(b) ?? epoch);
  return byDate != 0 ? byDate : (a['id'] as String).compareTo(b['id'] as String);
}
