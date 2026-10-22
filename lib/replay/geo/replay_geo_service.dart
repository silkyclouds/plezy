import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../media/ids.dart';
import '../client/replay_api_cache.dart';

/// Where the viewer is, as far as broadcasters can tell: the country their public IP address belongs to.
///
/// Catch-up rights follow the viewer's country, so the app compares it with each channel's rules to grey out what will
/// not play. The viewer can override it when an address misleads, for example behind a VPN or on a hotel network.
class ReplayGeoService {
  static const _endpoint = '/replay/geo';
  static const _timeout = Duration(seconds: 6);

  final http.Client _http;
  final ReplayApiCache? store;
  final ServerId _serverId;
  final Duration maxAge;
  final DateTime Function() _now;

  String? _detected;
  String? _override;
  DateTime? _detectedAt;
  bool _loaded = false;
  Future<void>? _loading;
  Future<void>? _detecting;

  ReplayGeoService({
    required http.Client client,
    this.store,
    ServerId? serverId,
    this.maxAge = const Duration(hours: 12),
    DateTime Function()? now,
  }) : _http = client,
       _serverId = serverId ?? ServerId('replay'),
       _now = now ?? DateTime.now;

  /// The country broadcasters should be compared against: the viewer's own choice, else the detected one, else null.
  String? get country => _override ?? _detected;

  /// The country found from the address, ignoring any override.
  String? get detected => _detected;

  String? get override => _override;

  /// Loads the last known values and, when they are stale or missing, asks the network. Safe to call often.
  Future<String?> resolve({bool refresh = false}) async {
    await (_loading ??= _load());
    final fresh = _detectedAt != null && _now().difference(_detectedAt!) < maxAge;
    if (refresh || !fresh) await (_detecting ??= _detect().whenComplete(() => _detecting = null));
    return country;
  }

  /// Sets or clears the viewer's own country (an ISO 3166-1 code, or null for automatic).
  Future<void> setOverride(String? code) async {
    _override = code == null || code.isEmpty ? null : code.toUpperCase();
    await _save();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final stored = await store?.get(_serverId, _endpoint);
    if (stored == null) return;
    _detected = stored['detected'] as String?;
    _override = stored['override'] as String?;
    final at = stored['at'] as String?;
    _detectedAt = at == null ? null : DateTime.tryParse(at);
  }

  Future<void> _save() async {
    await store?.put(_serverId, _endpoint, {
      'detected': _detected,
      'override': _override,
      'at': _detectedAt?.toIso8601String(),
    });
  }

  Future<void> _detect() async {
    final code = await _fromCloudflare() ?? await _fromIpwho() ?? await _fromCountryIs();
    if (code == null) return;
    _detected = code;
    _detectedAt = _now();
    await _save();
  }

  Future<String?> _fromCloudflare() async {
    final body = await _fetch('https://www.cloudflare.com/cdn-cgi/trace');
    final match = body == null ? null : RegExp(r'^loc=([A-Z]{2})$', multiLine: true).firstMatch(body);
    return match?.group(1);
  }

  Future<String?> _fromIpwho() async => _codeFromJson(await _fetch('https://ipwho.is/'), 'country_code');

  Future<String?> _fromCountryIs() async => _codeFromJson(await _fetch('https://api.country.is/'), 'country');

  String? _codeFromJson(String? body, String key) {
    if (body == null) return null;
    try {
      final value = (jsonDecode(body) as Map<String, dynamic>)[key];
      return value is String && RegExp(r'^[A-Za-z]{2}$').hasMatch(value) ? value.toUpperCase() : null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> _fetch(String url) async {
    try {
      final response = await _http.get(Uri.parse(url)).timeout(_timeout);
      return response.statusCode == 200 ? response.body : null;
    } on Exception {
      // A lookup that fails is not an error for the viewer: the next service is tried, then nothing is greyed out.
      return null;
    }
  }

  void close() => _http.close();
}
