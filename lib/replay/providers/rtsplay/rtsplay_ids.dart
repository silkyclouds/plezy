import '../../model/replay_ref.dart';

const rtsPlaySourceId = 'rtsplay';

/// Shows that hold unrelated one-off programmes (telefilms, specimens). Their items are films, not episodes.
const rtsFilmUmbrellaShows = {'1800017', '1772596'};

/// A show with more episodes than this is listed by broadcast year when its episodes carry no season number.
const rtsLongShowThreshold = 100;

final _safeId = RegExp(r'^[A-Za-z0-9-]+$');

/// What a native id points at.
///
/// Native ids are `show:<showId>`, `season:<showId>/<seasonKey>` and `video:<videoId>`. A season key is
/// `s<n>` for a numbered season, `y<year>` for one year of a long daily show, or `other` for episodes
/// the broadcaster gave no season number.
sealed class RtsId {
  const RtsId();

  static RtsId? tryParse(String native) {
    final cut = native.indexOf(':');
    if (cut <= 0) return null;
    final body = native.substring(cut + 1);
    switch (native.substring(0, cut)) {
      case 'show':
        return _safeId.hasMatch(body) ? RtsShowId(body) : null;
      case 'video':
        return _safeId.hasMatch(body) ? RtsVideoId(body) : null;
      case 'season':
        final parts = body.split('/');
        if (parts.length != 2 || !_safeId.hasMatch(parts[0])) return null;
        final key = RtsSeasonKey.tryParse(parts[1]);
        return key == null ? null : RtsSeasonId(parts[0], key);
    }
    return null;
  }
}

class RtsShowId extends RtsId {
  final String showId;

  const RtsShowId(this.showId);
}

class RtsSeasonId extends RtsId {
  final String showId;
  final RtsSeasonKey key;

  const RtsSeasonId(this.showId, this.key);

  ReplayRef get showRef => rtsShowRef(showId);
}

class RtsVideoId extends RtsId {
  final String videoId;

  const RtsVideoId(this.videoId);
}

/// How the episodes of a show are split into seasons.
class RtsSeasonKey {
  final int? number;
  final int? year;

  const RtsSeasonKey.numbered(int this.number) : year = null;
  const RtsSeasonKey.year(int this.year) : number = null;
  const RtsSeasonKey.other() : number = null, year = null;

  static RtsSeasonKey? tryParse(String raw) {
    if (raw == 'other') return const RtsSeasonKey.other();
    final value = int.tryParse(raw.length > 1 ? raw.substring(1) : '');
    if (value == null) return null;
    return switch (raw[0]) {
      's' => RtsSeasonKey.numbered(value),
      'y' => RtsSeasonKey.year(value),
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
  bool operator ==(Object other) => other is RtsSeasonKey && other.number == number && other.year == year;

  @override
  int get hashCode => Object.hash(number, year);
}

ReplayRef rtsShowRef(String showId) => ReplayRef(rtsPlaySourceId, 'show:$showId');

ReplayRef rtsVideoRef(String videoId) => ReplayRef(rtsPlaySourceId, 'video:$videoId');

ReplayRef rtsSeasonRef(String showId, RtsSeasonKey key) => ReplayRef(rtsPlaySourceId, 'season:$showId/$key');
