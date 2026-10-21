import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtlplay_api.dart';
import 'rtlplay_authenticator.dart';
import 'rtlplay_catalog.dart';
import 'rtlplay_categories.dart';
import 'rtlplay_ids.dart';
import 'rtlplay_images.dart';
import 'rtlplay_playback.dart';
import 'rtlplay_stream_service.dart';

/// RTL Play (Belgium): the catalogue is open, playback needs the viewer's own RTL account.
///
/// Anonymously it is browse-only. Signed in, it asks the stream service for streams and offers the ones
/// that are not DRM protected.
class RtlPlayProvider implements ReplayProvider, ReplayAccountSupport {
  static const _source = ReplaySource(
    id: rtlPlaySourceId,
    name: 'RTL Play',
    language: 'fr',
    support: ReplayPlaybackSupport.partial,
  );

  final RtlPlayCatalog _catalog;
  final RtlPlayAuthenticator _authenticator;
  final RtlPlayStreamService _streams;

  RtlPlayProvider(MediaServerHttpClient http) : this.withApi(RtlPlayApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  RtlPlayProvider.withApi(RtlPlayApi api) : this._(api, RtlPlayAuthenticator(api.transport));

  RtlPlayProvider._(RtlPlayApi api, this._authenticator)
    : _catalog = RtlPlayCatalog(api),
      _streams = RtlPlayStreamService(api.transport, _authenticator.refresh);

  @override
  ReplayAuthenticator get authenticator => _authenticator;

  @override
  void useSession(ReplaySession? session) => _streams.useSession(session);

  @override
  set onSessionRenewed(void Function(ReplaySession session)? listener) => _streams.onSessionRenewed = listener;

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => rtlPlayCategories;

  @override
  Future<List<ReplayRail>> home() => _catalog.rails(rtlPlayHomeStorefront);

  @override
  Future<List<ReplayRail>> category(String categoryId) => _catalog.rails(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) =>
      _catalog.listing(browseId, page: page, pageSize: _source.listingPageSize);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _catalog.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = RtlPlayId.tryParse(ref.nativeId);
    return id == null ? null : _catalog.title(id);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = RtlPlayId.tryParse(ref.nativeId);
    return id == null ? const [] : _catalog.children(id);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = RtlPlayId.tryParse(ref.nativeId);
    if (id == null || id.isSeason) return rtlPlayNotPlayable();
    try {
      final title = await _catalog.title(id);
      if (title == null) return rtlPlayGone();
      if (!title.isPlayable) return rtlPlayNotPlayable();
      return _streams.isSignedIn ? await _streams.resolve(id.episode ?? id.programme) : rtlPlayLoginRequired();
    } on RtlPlayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on RtlPlayVersionRejectedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => rtlPlayImageUrl(reference);

  @override
  bool ownsImage(String reference) => isRtlPlayImage(reference);

  @override
  void close() {}
}
