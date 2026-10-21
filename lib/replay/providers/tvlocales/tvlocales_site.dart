import 'tvlocales_models.dart';

/// How one station site lists its shows and episodes. Each site generator has its own implementation.
abstract interface class TvLocalesSite {
  /// How many slices of a show's episode list [showPage] may be asked for.
  int get maxEpisodePages;

  Future<List<TvShowCard>> showCards();

  /// One slice of a show's episodes. [seasonFacet] selects a season when the show has some.
  /// Throws the HTTP exception of the site when the show does not exist.
  Future<TvShowPage> showPage(String slug, {String? seasonFacet, int page = 0});

  /// The page of an episode, by the path that follows the show slug.
  Future<TvEpisodePage> episodePage(String showSlug, String episodePath);
}
