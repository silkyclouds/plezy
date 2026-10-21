/// Which site generator a station runs, which decides how its pages are read.
enum TvLocalesSiteKind { drupal, tvlux }

/// Everything that differs between two channels of the Freecaster network.
class TvLocalesStation {
  /// Source id the app stores in item ids.
  final String id;
  final String name;
  final String host;

  /// Path segment Freecaster uses for the station's videos and posters.
  final String customer;
  final TvLocalesSiteKind kind;

  /// Show whose newest episodes open the home page; null leaves the home to the show list.
  final String? latestShowSlug;

  const TvLocalesStation({
    required this.id,
    required this.name,
    required this.host,
    required this.customer,
    required this.kind,
    this.latestShowSlug,
  });

  Uri get base => Uri.https(host);
}
