import 'dart:async';

import '../../model/replay_ref.dart';
import 'orftvthek_api.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_json.dart';
import 'orftvthek_shows.dart';

const _imageKeys = ['image', 'image16x9_with_logo', 'image2x3_with_logo', 'image2x3', 'image12x5'];

/// One ORF profile, reduced to what listing a show needs.
class OrfProfile {
  final int id;

  /// The season this profile is of its show, when ORF names it `<show> Staffel <n>`.
  final int? season;
  final int episodeCount;
  final int newestEpisodeId;
  final Map<String, dynamic> profile;

  const OrfProfile({
    required this.id,
    required this.season,
    required this.episodeCount,
    required this.newestEpisodeId,
    required this.profile,
  });

  /// Keeps the fields a show card needs from a full profile object.
  factory OrfProfile.fromJson(Map<String, dynamic> item, {required int id, int? season}) => OrfProfile(
    id: id,
    season: season,
    episodeCount: orfInt(item['online_episode_count']) ?? 0,
    newestEpisodeId: orfInt(item['newest_episode_id']) ?? 0,
    profile: <String, dynamic>{
      for (final key in ['id', 'title', 'headline', 'description', 'online_episode_count', 'newest_episode_id'])
        if (item[key] != null) key: item[key],
      '_embedded': <String, dynamic>{for (final key in _imageKeys) key: ?orfMap(orfMap(item['_embedded'])?[key])},
    },
  );
}

/// A show as the viewer sees it: one profile, or the profiles that ORF publishes season by season.
class OrfShowGroup {
  final ReplayRef ref;
  final String title;

  /// Ordered by season number for a series.
  final List<OrfProfile> profiles;

  const OrfShowGroup(this.ref, this.title, this.profiles);

  bool get isSeries => profiles.any((p) => p.season != null);

  /// The profile with the latest episode, whose text and pictures describe the show best.
  OrfProfile get newest => profiles.reduce((a, b) => b.newestEpisodeId > a.newestEpisodeId ? b : a);

  OrfProfile? profileById(int id) => profiles.where((p) => p.id == id).firstOrNull;
}

/// The alphabetical list of every show, read once and kept for a few hours.
///
/// A profile list is megabytes at the size the API pages it, so only the fields a card needs are kept. The list is
/// what turns the separate "Staffel" profiles into one show with seasons.
class OrfProfileIndex {
  static const _lifetime = Duration(hours: 12);
  static const _pageSize = 500;
  static const _maxPages = 6;

  final OrfApi _api;
  final DateTime Function() _now;
  ({DateTime at, Future<List<OrfShowGroup>> groups})? _cached;

  OrfProfileIndex(this._api, this._now);

  Future<List<OrfShowGroup>> groups() {
    final cached = _cached;
    if (cached != null && _now().difference(cached.at) < _lifetime) return cached.groups;
    final loading = _load();
    _cached = (at: _now(), groups: loading);
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_cached?.groups, loading)) _cached = null;
        },
      ),
    );
    return loading;
  }

  /// The show a ref names: a series by key, or the show that holds a profile.
  Future<OrfShowGroup?> byRef(ReplayRef ref) async {
    final target = parseOrfRef(ref);
    final all = await groups();
    return switch (target) {
      OrfSeriesTarget(:final key) => all.where((g) => g.ref == orfSeriesRef(key)).firstOrNull,
      OrfProfileTarget(:final id) => _holding(all, id),
      _ => null,
    };
  }

  Future<OrfShowGroup?> byProfileId(int id) async => _holding(await groups(), id);

  OrfShowGroup? _holding(List<OrfShowGroup> all, int profileId) =>
      all.where((g) => g.profileById(profileId) != null).firstOrNull;

  Future<List<OrfShowGroup>> _load() async {
    final first = await _api.profiles(limit: _pageSize);
    final pages = (orfInt(first['pages']) ?? 1).clamp(1, _maxPages);
    final rest = await Future.wait([
      for (var page = 2; page <= pages; page++) _api.profiles(page: page, limit: _pageSize),
    ]);
    return _group([
      for (final page in [first, ...rest]) ...orfItems(page),
    ]);
  }

  List<OrfShowGroup> _group(List<Map<String, dynamic>> items) {
    final seen = <int>{};
    final members = <String, List<OrfProfile>>{};
    final titles = <String, String>{};
    final refs = <String, ReplayRef>{};
    for (final item in items) {
      final id = orfInt(item['id']);
      final title = orfString(item['title']) ?? orfString(item['headline']);
      if (id == null || title == null || !orfIsListedProfile(item) || !seen.add(id)) continue;
      final identity = OrfShowIdentity.of(id, title);
      final key = identity.ref.nativeId;
      refs[key] = identity.ref;
      titles.putIfAbsent(key, () => identity.title);
      members.putIfAbsent(key, () => []).add(OrfProfile.fromJson(item, id: id, season: identity.season));
    }
    return [for (final key in members.keys) OrfShowGroup(refs[key]!, titles[key]!, _bySeason(members[key]!))];
  }

  List<OrfProfile> _bySeason(List<OrfProfile> profiles) =>
      profiles.length < 2 ? profiles : (List.of(profiles)..sort((a, b) => (a.season ?? 0).compareTo(b.season ?? 0)));
}
