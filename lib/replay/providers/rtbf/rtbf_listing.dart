import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtbf_bff.dart';
import 'rtbf_mapper.dart';

const _fetchSize = 50;

/// Server pages read for one client page at most, in case a long run of them holds nothing the app keeps.
const _maxFetchesPerPage = 10;
const _bufferTtl = Duration(minutes: 10);
const _widgetPrefix = 'widget:';

/// Serves fixed-size pages of a mosaic whose server pages hold audio that this app drops.
///
/// The server pages cannot be mapped one to one onto client pages once entries are removed, so each
/// listing keeps the titles it has read so far and reads further server pages only as far as the
/// requested page needs.
class RtbfListing {
  final RtbfBff _bff;
  final RtbfMapper _mapper;
  final DateTime Function() _now;
  final Map<String, _Buffer> _buffers = {};

  RtbfListing(this._bff, this._mapper, this._now);

  /// Page [page] (zero-based) of [pageSize] titles. [browseId] is [replayAllBrowseId] or `widget:<id>`.
  Future<ReplayPage> page(String browseId, int page, int pageSize) async {
    final first = _firstPath(browseId);
    if (first == null) return const ReplayPage(titles: [], totalCount: 0);

    final buffer = _bufferFor(browseId, first);
    final needed = (page + 1) * pageSize;
    await buffer.serialize(() => _fill(buffer, needed));

    final start = page * pageSize;
    final end = needed < buffer.titles.length ? needed : buffer.titles.length;
    return ReplayPage(
      titles: start < end ? buffer.titles.sublist(start, end) : const [],
      totalCount: buffer.estimatedTotal(pageSize),
    );
  }

  _Buffer _bufferFor(String browseId, String firstPath) {
    final known = _buffers[browseId];
    if (known != null && _now().difference(known.loadedAt) <= _bufferTtl) return known;
    return _buffers[browseId] = _Buffer(firstPath, _now());
  }

  String? _firstPath(String browseId) {
    if (browseId == replayAllBrowseId) return 'mosaic/program?includeFastTv=true&_page=1&_limit=$_fetchSize';
    if (browseId.startsWith(_widgetPrefix)) {
      final id = Uri.encodeQueryComponent(browseId.substring(_widgetPrefix.length));
      return 'mosaic/widget?id=$id&_page=1&_limit=$_fetchSize';
    }
    return null;
  }

  Future<void> _fill(_Buffer buffer, int needed) async {
    for (
      var fetches = 0;
      buffer.titles.length < needed && buffer.next != null && fetches < _maxFetchesPerPage;
      fetches++
    ) {
      final body = await _bff.find(buffer.next!);
      if (body == null) {
        buffer.next = null;
        break;
      }
      final cards = body['data'];
      final kept = _mapper.cards(cards is List ? cards : const []);
      buffer.dropped += (cards is List ? cards.length : 0) - kept.length;
      for (final title in kept) {
        if (buffer.seen.add(title.ref)) buffer.titles.add(title);
      }
      buffer.serverTotal ??= ((body['meta'] as Map?)?['page'] as Map?)?['totalCount'] as int?;
      final next = (body['links'] as Map?)?['next'];
      buffer.next = next is String ? next : null;
    }
  }
}

class _Buffer {
  final DateTime loadedAt;
  final List<ReplayTitle> titles = [];
  final Set<ReplayRef> seen = {};
  String? next;
  int dropped = 0;
  int? serverTotal;
  Future<void> _tail = Future.value();

  _Buffer(this.next, this.loadedAt);

  /// Runs [job] after the jobs queued before it, so concurrent page requests do not read the same server page twice.
  Future<void> serialize(Future<void> Function() job) {
    final run = _tail.then((_) => job());
    // The caller receives the failure through [run]; the queue itself must outlive it.
    _tail = run.catchError((Object _) {});
    return run;
  }

  /// Exact once every server page is read; before that the server's own count minus what was dropped so far.
  int estimatedTotal(int pageSize) {
    if (next == null) return titles.length;
    final total = serverTotal;
    return total == null ? titles.length + pageSize : total - dropped;
  }
}
