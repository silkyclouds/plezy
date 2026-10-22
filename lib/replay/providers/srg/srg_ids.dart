final _safeId = RegExp(r'^[A-Za-z0-9-]+$');

/// True for an id that is safe to put in a request path.
bool isSrgSafeId(String id) => _safeId.hasMatch(id);

/// What a native id points at.
///
/// Native ids are `show:<showId>`, `season:<showId>/<seasonKey>` and `video:<videoId>`. A season key is
/// `s<n>` for a numbered season, `y<year>` for one year of a long daily show, or `other` for episodes
/// the broadcaster gave no season number.
sealed class SrgId {
  const SrgId();

  static SrgId? tryParse(String native) {
    final cut = native.indexOf(':');
    if (cut <= 0) return null;
    final body = native.substring(cut + 1);
    switch (native.substring(0, cut)) {
      case 'show':
        return isSrgSafeId(body) ? SrgShowId(body) : null;
      case 'video':
        return isSrgSafeId(body) ? SrgVideoId(body) : null;
      case 'season':
        final parts = body.split('/');
        if (parts.length != 2 || !isSrgSafeId(parts[0])) return null;
        final key = SrgSeasonKey.tryParse(parts[1]);
        return key == null ? null : SrgSeasonId(parts[0], key);
    }
    return null;
  }
}

class SrgShowId extends SrgId {
  final String showId;

  const SrgShowId(this.showId);
}

class SrgSeasonId extends SrgId {
  final String showId;
  final SrgSeasonKey key;

  const SrgSeasonId(this.showId, this.key);
}

class SrgVideoId extends SrgId {
  final String videoId;

  const SrgVideoId(this.videoId);
}

/// How the episodes of a show are split into seasons.
class SrgSeasonKey {
  final int? number;
  final int? year;

  const SrgSeasonKey.numbered(int this.number) : year = null;
  const SrgSeasonKey.year(int this.year) : number = null;
  const SrgSeasonKey.other() : number = null, year = null;

  static SrgSeasonKey? tryParse(String raw) {
    if (raw == 'other') return const SrgSeasonKey.other();
    final value = int.tryParse(raw.length > 1 ? raw.substring(1) : '');
    if (value == null) return null;
    return switch (raw[0]) {
      's' => SrgSeasonKey.numbered(value),
      'y' => SrgSeasonKey.year(value),
      _ => null,
    };
  }

  bool get isOther => number == null && year == null;

  @override
  String toString() => number != null
      ? 's$number'
      : year != null
      ? 'y$year'
      : 'other';

  @override
  bool operator ==(Object other) => other is SrgSeasonKey && other.number == number && other.year == year;

  @override
  int get hashCode => Object.hash(number, year);
}
