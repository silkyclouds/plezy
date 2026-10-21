import '../tvlocales_api.dart';
import '../tvlocales_episode_page.dart';
import '../tvlocales_models.dart';
import '../tvlocales_site.dart';
import 'tvlux_parser.dart';

/// TV Lux: its own site, with no seasons and one list of the newest 24 episodes per show.
class TvLuxSite implements TvLocalesSite {
  final TvLocalesApi _api;
  final Uri _base;

  TvLuxSite(this._api, this._base);

  @override
  int get maxEpisodePages => 1;

  @override
  Future<List<TvShowCard>> showCards() async => parseTvLuxShows(await _api.page(_base.resolve('/replay')), _base);

  @override
  Future<TvShowPage> showPage(String slug, {String? seasonFacet, int page = 0}) async =>
      parseTvLuxShowPage(await _api.page(_base.resolve('/replay/$slug')), _base, slug);

  @override
  Future<TvEpisodePage> episodePage(String showSlug, String episodePath) async =>
      parseEpisodePage(await _api.page(_base.resolve('/replay/$showSlug/$episodePath')));
}
