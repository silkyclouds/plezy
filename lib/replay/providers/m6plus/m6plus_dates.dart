/// Reads the catalogue's `YYYY-MM-DD HH:MM:SS` stamps, which carry no zone, as UTC. They are Paris wall-clock
/// times, so comparisons against now can be off by an hour or two; none of them decides anything finer than that.
/// Several stamps joined by commas are reduced to the first.
DateTime? m6plusDate(Object? raw) {
  final text = raw is Map ? raw['date'] : raw;
  if (text is! String || text.isEmpty) return null;
  final first = text.split(',').first.trim();
  return DateTime.tryParse('${first.replaceFirst(' ', 'T')}Z');
}
