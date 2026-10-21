final _segment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._%-]*$');

/// Native id of a title, which says what the title is by its shape.
///
/// - show: `<slug>`
/// - season: `<slug>/~<facet>`, where the facet is a season number of the station site or `all`
/// - episode: `<slug>/<path>`, the rest of the episode page address on the station site
class TvLocalesId {
  /// Season id of a show whose site has no seasons: every episode in one list.
  static const allEpisodes = 'all';

  final String showSlug;
  final String? seasonFacet;
  final String? episodePath;

  const TvLocalesId._(this.showSlug, {this.seasonFacet, this.episodePath});

  const TvLocalesId.show(String slug) : this._(slug);

  const TvLocalesId.season(String slug, String facet) : this._(slug, seasonFacet: facet);

  bool get isShow => seasonFacet == null && episodePath == null;
  bool get isSeason => seasonFacet != null;
  bool get isEpisode => episodePath != null;

  /// The id as stored in a [ReplayRef].
  String get nativeId {
    if (isSeason) return '$showSlug/~$seasonFacet';
    return isEpisode ? '$showSlug/$episodePath' : showSlug;
  }

  /// Parses a native id. Returns null for anything that could not be a path on a station site.
  static TvLocalesId? tryParse(String nativeId) {
    final parts = nativeId.split('/');
    if (parts.length > 4) return null;
    final season = _seasonOf(parts);
    if (season != null) return season;
    if (!parts.every(_segment.hasMatch)) return null;
    if (parts.length == 1) return TvLocalesId.show(parts.first);
    return TvLocalesId._(parts.first, episodePath: parts.skip(1).join('/'));
  }

  static TvLocalesId? _seasonOf(List<String> parts) {
    if (parts.length != 2 || !parts[1].startsWith('~')) return null;
    final facet = parts[1].substring(1);
    return _segment.hasMatch(parts[0]) && _segment.hasMatch(facet) ? TvLocalesId.season(parts[0], facet) : null;
  }

  @override
  bool operator ==(Object other) => other is TvLocalesId && other.nativeId == nativeId;

  @override
  int get hashCode => nativeId.hashCode;
}
