import '../../model/replay_ref.dart';

const pbsSourceId = 'pbs';

/// Season key of the synthetic season that holds a show's stand-alone specials and films.
const pbsSpecialsSeason = 'specials';

final _slug = RegExp(r'^[A-Za-z0-9_-]+$');
final _numeric = RegExp(r'^[0-9]+$');
final _cid = RegExp(r'^[0-9a-f-]{36}$');

/// What a native id points at.
///
/// Native ids are `show:<slug>`, `season:<slug>/<cid>` (or `season:<slug>/specials`) and `video:<mediaId>/<slug>`.
/// The media id feeds the player page, the slug feeds the video's own page.
sealed class PbsId {
  const PbsId();

  static PbsId? tryParse(String native) {
    final cut = native.indexOf(':');
    if (cut <= 0) return null;
    final body = native.substring(cut + 1);
    final parts = body.split('/');
    switch (native.substring(0, cut)) {
      case 'show' when parts.length == 1 && _slug.hasMatch(body):
        return PbsShowId(body);
      case 'season' when parts.length == 2 && _slug.hasMatch(parts[0]):
        return _cid.hasMatch(parts[1]) || parts[1] == pbsSpecialsSeason ? PbsSeasonId(parts[0], parts[1]) : null;
      case 'video' when parts.length == 2 && _numeric.hasMatch(parts[0]) && _slug.hasMatch(parts[1]):
        return PbsVideoId(parts[0], parts[1]);
    }
    return null;
  }
}

class PbsShowId extends PbsId {
  final String slug;

  const PbsShowId(this.slug);
}

class PbsSeasonId extends PbsId {
  final String showSlug;

  /// The season's content id, or [pbsSpecialsSeason].
  final String seasonKey;

  const PbsSeasonId(this.showSlug, this.seasonKey);

  bool get isSpecials => seasonKey == pbsSpecialsSeason;
}

class PbsVideoId extends PbsId {
  final String mediaId;
  final String slug;

  const PbsVideoId(this.mediaId, this.slug);
}

ReplayRef pbsShowRef(String slug) => ReplayRef(pbsSourceId, 'show:$slug');

ReplayRef pbsSeasonRef(String showSlug, String seasonKey) => ReplayRef(pbsSourceId, 'season:$showSlug/$seasonKey');

ReplayRef pbsVideoRef(String mediaId, String slug) => ReplayRef(pbsSourceId, 'video:$mediaId/$slug');
