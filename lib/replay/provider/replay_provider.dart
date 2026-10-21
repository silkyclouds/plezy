import '../model/replay_playback.dart';
import '../model/replay_ref.dart';
import '../model/replay_title.dart';

/// How much of a broadcaster the app can actually play.
enum ReplayPlaybackSupport {
  /// Unprotected streams for most of the catalogue.
  clear,

  /// Some titles play, many are protected or need an account.
  partial,

  /// Browsing and search only: every stream is protected.
  browseOnly,
}

/// Browse id of the listing that holds a source's whole catalogue.
const replayAllBrowseId = 'all';

/// Static description of a broadcaster.
class ReplaySource {
  final String id;
  final String name;
  final String language;
  final ReplayPlaybackSupport support;

  /// Titles per page of [ReplayProvider.listing], fixed by the broadcaster.
  final int listingPageSize;

  const ReplaySource({
    required this.id,
    required this.name,
    required this.language,
    required this.support,
    this.listingPageSize = 20,
  });
}

/// One broadcaster's catalogue and playback resolution.
///
/// Implementations return [ReplayTitle]s whose [ReplayRef.source] equals
/// [source].id, and never throw for an empty catalogue: they return empty lists.
abstract interface class ReplayProvider {
  ReplaySource get source;

  /// Top-level sections the user can open from the source's page.
  Future<List<ReplayCategory>> categories();

  /// The rows of the source's landing page.
  Future<List<ReplayRail>> home();

  /// The rows of one category page.
  Future<List<ReplayRail>> category(String categoryId);

  /// A flat listing, used by "see all" and by libraries that show a grid. [replayAllBrowseId] is the
  /// whole catalogue. [page] is zero-based and holds [ReplaySource.listingPageSize] titles.
  Future<ReplayPage> listing(String browseId, {int page = 0});

  Future<List<ReplayTitle>> search(String query);

  /// One title by native id, or null when the broadcaster no longer has it.
  Future<ReplayTitle?> title(ReplayRef ref);

  /// Seasons of a show, or episodes of a season. A show without seasons returns its episodes.
  Future<List<ReplayTitle>> children(ReplayRef ref);

  /// Resolves how to play an episode, movie or clip.
  Future<ReplayPlayback> playback(ReplayRef ref);

  /// Turns an artwork reference from a [ReplayTitle] into a fetchable URL, sized when the source can resize.
  String imageUrl(String reference, {int? width, int? height});

  /// Whether [reference] is an artwork reference this provider produced.
  bool ownsImage(String reference);

  void close();
}
