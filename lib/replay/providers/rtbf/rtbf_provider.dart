import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtbf_api.dart';
import 'rtbf_auth.dart';
import 'rtbf_catalog.dart';
import 'rtbf_categories.dart';
import 'rtbf_http.dart';
import 'rtbf_images.dart';
import 'rtbf_listing.dart';
import 'rtbf_mapper.dart';
import 'rtbf_playback.dart';
import 'rtbf_rails.dart';
import 'rtbf_rights.dart';

/// Auvio (RTBF): the whole catalogue browses anonymously, but only a minority of titles play.
///
/// Fiction, kids and most films are DRM-protected, and most recent replay needs a free RTBF account.
/// Archives, magazines and educational programmes play as clear HLS. Signed in with that account, the
/// provider plays what it is entitled to; protected streams stay unavailable.
class RtbfProvider implements ReplayProvider, ReplayAccountSupport {
  static const _source = ReplaySource(
    id: rtbfSourceId,
    name: 'Auvio',
    language: 'fr',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 50,
  );

  final RtbfApi _api;
  final DateTime Function() _now;
  ReplaySession? _session;
  void Function(ReplaySession session)? _onSessionRenewed;
  Future<String?>? _renewing;

  late final RtbfMapper _mapper = RtbfMapper(_now);
  late final RtbfRights _rights = RtbfRights(_api.exposure, _now);
  late final RtbfCatalog _catalog = RtbfCatalog(_api.bff, _mapper, _rights);
  late final RtbfRails _rails = RtbfRails(_api.bff, _mapper);
  late final RtbfListing _listing = RtbfListing(_api.bff, _mapper, _now);
  late final RtbfAuthenticator _authenticator = RtbfAuthenticator(_api.http, _api.exposure.deviceId);

  RtbfProvider(MediaServerHttpClient http, {String? deviceId}) : this.withApi(RtbfApi(http, deviceId: deviceId));

  /// Test seam: a provider over an API whose responses the caller controls.
  RtbfProvider.withApi(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    _api.exposure.renewUserToken = _renewSession;
  }

  @override
  ReplaySource get source => _source;

  @override
  ReplayAuthenticator get authenticator => _authenticator;

  @override
  void useSession(ReplaySession? session) {
    _session = session;
    _api.exposure.useUserToken(rtbfSessionToken(session));
  }

  @override
  set onSessionRenewed(void Function(ReplaySession session)? listener) => _onSessionRenewed = listener;

  @override
  Future<List<ReplayCategory>> categories() => rtbfCategories(_api.bff);

  @override
  Future<List<ReplayRail>> home() async => _rails.fromPage(await _api.bff.get('pages/home'));

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    if (!isRtbfCategoryId(categoryId)) return const [];
    final page = await _api.bff.find('pages/$categoryId');
    return page == null ? const [] : _rails.fromPage(page);
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _listing.page(browseId, page, _source.listingPageSize);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final body = await _api.bff.get('search', query: {'query': trimmed});
    final sections = body['data'];
    if (sections is! List) return const [];
    final programs = _section(sections, 'PROGRAM_LIST');
    final media = _section(sections, 'MEDIA_LIST');
    return _mapper.cards([...programs, ...media]);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (_isMedia(id)) return _catalog.media(id.substring(1));
    if (!_isProgram(id)) return null;
    if (id.contains('/')) {
      final seasons = await _catalog.seasons(_programId(id));
      return seasons.where((s) => s.ref == ref).firstOrNull;
    }
    return _catalog.show(_programId(id));
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = ref.nativeId;
    if (!_isProgram(id)) return const [];
    return id.contains('/') ? _catalog.episodes(ref) : _catalog.seasons(_programId(id));
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final mediaId = await _mediaIdToPlay(ref.nativeId);
    if (mediaId == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return rtbfParsePlayback(await _api.exposure.entitlement(mediaId), _now());
    } on RtbfRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => rtbfImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isRtbfImage(reference);

  @override
  void close() {}

  /// Renews the account session when Red Bee rejects it, once at a time, and hands the new one to the
  /// listener so it is stored. Null when there is nothing to renew from or the account refuses.
  Future<String?> _renewSession() => _renewing ??= _renewNow().whenComplete(() => _renewing = null);

  Future<String?> _renewNow() async {
    final current = _session;
    if (current == null) return null;
    try {
      final fresh = await _authenticator.renew(current);
      _session = fresh;
      _onSessionRenewed?.call(fresh);
      return rtbfSessionToken(fresh);
    } on ReplayAuthException {
      return null;
    }
  }

  /// A media plays directly; a one-off programme plays its single film; shows and seasons play nothing.
  Future<String?> _mediaIdToPlay(String id) async {
    if (_isMedia(id)) return id.substring(1);
    if (_isProgram(id) && !id.contains('/')) return _catalog.standaloneMediaId(_programId(id));
    return null;
  }

  List<Object?> _section(List<Object?> sections, String type) {
    for (final section in sections.whereType<Map<String, dynamic>>()) {
      if (section['type'] == type && section['content'] is List) return section['content'] as List<Object?>;
    }
    return const [];
  }

  bool _isMedia(String id) => id.startsWith('m');

  bool _isProgram(String id) => id.startsWith('p');

  String _programId(String id) => id.substring(1).split('/').first;
}
