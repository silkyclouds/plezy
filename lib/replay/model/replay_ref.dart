/// Identifies one title inside one broadcaster: `source:nativeId`.
///
/// The string form is the id stored in `MediaItem.id`, so it must survive a
/// round trip through the database and deep links unchanged.
class ReplayRef {
  final String source;
  final String nativeId;

  const ReplayRef(this.source, this.nativeId);

  /// Parses `source:nativeId`. Native ids may themselves contain colons.
  static ReplayRef? tryParse(String raw) {
    final cut = raw.indexOf(':');
    if (cut <= 0 || cut == raw.length - 1) return null;
    return ReplayRef(raw.substring(0, cut), raw.substring(cut + 1));
  }

  @override
  String toString() => '$source:$nativeId';

  @override
  bool operator ==(Object other) => other is ReplayRef && other.source == source && other.nativeId == nativeId;

  @override
  int get hashCode => Object.hash(source, nativeId);
}
