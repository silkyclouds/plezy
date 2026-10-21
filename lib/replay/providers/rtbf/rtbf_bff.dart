import '../../../exceptions/media_server_exceptions.dart';
import 'rtbf_http.dart';

const _bffBase = 'https://bff-service.rtbf.be/auvio';
const _siteHome = 'https://auvio.rtbf.be/';
const _initialVersion = 'v1.23';
const _cacheTtl = Duration(minutes: 3);

/// The website's backend-for-frontend: pages, widgets, mosaics and search, all anonymous.
///
/// The API version lives in every URL and old versions answer 410, so it is read back from the
/// website when that happens and rewritten into links the server handed out earlier.
class RtbfBff {
  final RtbfHttp _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  String _version = _initialVersion;

  RtbfBff(this._http, this._now);

  /// A BFF path such as `pages/home` or an absolute link taken from a response. Cached for a few minutes.
  Future<Map<String, dynamic>> get(String target, {Map<String, String>? query}) async {
    final answer = await _load(target, query);
    return answer.isOk ? answer.body : throw _failure(answer);
  }

  /// Like [get], but an unknown id (HTTP 404) gives null.
  Future<Map<String, dynamic>?> find(String target, {Map<String, String>? query}) async {
    final answer = await _load(target, query);
    if (answer.isOk) return answer.body;
    return answer.status == 404 ? null : throw _failure(answer);
  }

  MediaServerHttpException _failure(RtbfAnswer answer) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: answer.status,
    responseData: answer.body,
    message: 'HTTP ${answer.status}',
  );

  Future<RtbfAnswer> _load(String target, Map<String, String>? query) async {
    var answer = await _fetch(target, query);
    if (answer.status == 410) {
      await _refreshVersion();
      answer = await _fetch(target, query);
    }
    return answer;
  }

  Future<RtbfAnswer> _fetch(String target, Map<String, String>? query) async {
    final url = _url(target, query).toString();
    final hit = _cache[url];
    if (hit != null && _now().difference(hit.at) < _cacheTtl) return RtbfAnswer(200, hit.body);
    final answer = await _http.getJson(url, tolerate: const {404, 410});
    if (answer.isOk) _cache[url] = (at: _now(), body: answer.body);
    return answer;
  }

  Uri _url(String target, Map<String, String>? query) {
    final isLink = target.startsWith('http');
    final base = isLink
        ? Uri.parse(target.replaceFirst(RegExp(r'/auvio/v\d+\.\d+/'), '/auvio/$_version/'))
        : Uri.parse('$_bffBase/$_version/$target');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  Future<void> _refreshVersion() async {
    final html = await _http.getText(_siteHome);
    final match = RegExp(r'bff-service\.rtbf\.be/auvio/(v\d+\.\d+)/').firstMatch(html);
    if (match == null) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: 410,
        message: 'API version retired and the website does not name a new one',
      );
    }
    _version = match.group(1)!;
    _cache.clear();
  }
}
