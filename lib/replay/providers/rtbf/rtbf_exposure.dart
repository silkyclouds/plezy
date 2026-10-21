import 'dart:math';

import '../../../exceptions/media_server_exceptions.dart';
import 'rtbf_http.dart';

const _unit = 'https://exposure.api.redbee.live';
const _scope = 'customer/RTBF/businessunit/Auvio';

/// Base of the Red Bee calls that need a session: sign-in, session checks and play entitlements.
const rtbfExposureV2 = '$_unit/v2/$_scope';
const _assetSuffix = '6BA97Bb';
const _assetTtl = Duration(minutes: 10);
const _renewBefore = Duration(minutes: 10);

/// The body that names this install to Red Bee, for anonymous and account sessions alike.
Map<String, Object> rtbfDeviceBody(String deviceId) => {
  'device': {'name': 'Plezy', 'type': 'WEB'},
  'deviceId': deviceId,
};

/// Red Bee asset id for an Auvio media id.
String rtbfAssetId(String mediaId) => '${mediaId}_$_assetSuffix';

/// The OTT platform behind Auvio playback: an anonymous or signed-in session, asset rights and play entitlements.
class RtbfExposure {
  final RtbfHttp _http;
  final DateTime Function() _now;
  final String deviceId;
  final Map<String, ({DateTime at, Map<String, dynamic>? body})> _assets = {};
  Future<String>? _pendingSession;
  String? _token;
  DateTime? _tokenExpiry;
  String? _userToken;

  /// Asked for a new account token when Red Bee rejects the current one; null when it cannot renew.
  Future<String?> Function()? renewUserToken;

  RtbfExposure(this._http, this._now, {String? deviceId}) : deviceId = deviceId ?? _randomDeviceId();

  bool get isSignedIn => _userToken != null;

  /// Plays as the account owning [token], or anonymously again when it is null. Asset records and
  /// the anonymous session do not depend on the account and are kept.
  void useUserToken(String? token) => _userToken = token;

  /// The asset record of a media, which lists its publications. Null when the platform does not know the id.
  Future<Map<String, dynamic>?> asset(String mediaId) async {
    final hit = _assets[mediaId];
    if (hit != null && _now().difference(hit.at) < _assetTtl) return hit.body;
    final answer = await _http.getJson(
      '$_unit/v1/$_scope/content/asset/${rtbfAssetId(mediaId)}',
      tolerate: const {404},
    );
    final body = answer.isOk ? answer.body : null;
    _assets[mediaId] = (at: _now(), body: body);
    return body;
  }

  /// Asks to play a media. Refusals (403, 404) come back as answers because their body says why.
  ///
  /// HLS is requested for libmpv and MP3 for audio-only items; DASH is never requested because the
  /// platform strips subtitles from it.
  Future<RtbfAnswer> entitlement(String mediaId) async {
    final url =
        '$rtbfExposureV2/entitlement/${rtbfAssetId(mediaId)}/play?supportedFormats=hls,mp3&supportedDrms=widevine';
    var answer = await _http.getJson(url, headers: await _auth(), tolerate: _refusals);
    if (answer.status == 401) {
      if (isSignedIn) {
        if (await _renewUser() == null) return answer;
      } else {
        _token = null;
      }
      answer = await _http.getJson(url, headers: await _auth(), tolerate: _refusals);
    }
    return answer;
  }

  /// Renews the account session once. A dead one that cannot be renewed is reported, never replaced by
  /// an anonymous one.
  Future<String?> _renewUser() async {
    final token = await renewUserToken?.call();
    if (token != null) _userToken = token;
    return token;
  }

  static const _refusals = {400, 401, 403, 404, 409};

  Future<Map<String, String>> _auth() async => {'Authorization': 'Bearer ${_userToken ?? await _sessionToken()}'};

  Future<String> _sessionToken() {
    final token = _token;
    final expiry = _tokenExpiry;
    if (token != null && expiry != null && expiry.difference(_now()) > _renewBefore) return Future.value(token);
    return _pendingSession ??= _openSession().whenComplete(() => _pendingSession = null);
  }

  Future<String> _openSession() async {
    final answer = await _http.postJson('$rtbfExposureV2/auth/anonymous', rtbfDeviceBody(deviceId));
    final token = answer.body['sessionToken'];
    if (token is! String) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: answer.status,
        message: 'The session answer holds no token',
      );
    }
    _token = token;
    _tokenExpiry =
        DateTime.tryParse(answer.body['expirationDateTime'] as String? ?? '') ?? _now().add(const Duration(days: 1));
    return token;
  }

  static String _randomDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
