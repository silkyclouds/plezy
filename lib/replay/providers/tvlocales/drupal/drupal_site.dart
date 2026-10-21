import '../tvlocales_api.dart';
import '../tvlocales_episode_page.dart';
import '../tvlocales_models.dart';
import '../tvlocales_site.dart';
import 'drupal_show_page_parser.dart';
import 'drupal_shows_parser.dart';

/// The five stations built on the same Drupal theme.
class DrupalSite implements TvLocalesSite {
  final TvLocalesApi _api;
  final Uri _base;

  DrupalSite(this._api, this._base);

  /// Eight episodes per slice, so six slices reach the last 48 editions without hammering the site.
  @override
  int get maxEpisodePages => 6;

  @override
  Future<List<TvShowCard>> showCards() async => parseDrupalShows(await _api.page(_base.resolve('/emissions')), _base);

  @override
  Future<TvShowPage> showPage(String slug, {String? seasonFacet, int page = 0}) async {
    final query = {if (seasonFacet != null) 'f[0]': 'saison:$seasonFacet', if (page > 0) 'page': '$page'};
    final uri = _base.replace(path: '/emission/$slug', queryParameters: query.isEmpty ? null : query);
    return parseDrupalShowPage(await _api.page(uri), _base, slug);
  }

  @override
  Future<TvEpisodePage> episodePage(String showSlug, String episodePath) async =>
      parseEpisodePage(await _api.page(_base.resolve('/replay/emission/$showSlug/$episodePath')));
}
