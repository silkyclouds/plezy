/// Cookies of the few hosts a sign-in visits, kept per host name.
///
/// The web flow hands its result over in cookies, so the jar is what carries a sign-in between redirects.
/// Hosts here never set a Domain attribute, so every cookie is treated as host-only.
class RtlPlayCookieJar {
  static final _setCookieSeparator = RegExp(r',(?=\s*[^;,=\s]+=)');

  final Map<String, Map<String, String>> _byHost = {};

  RtlPlayCookieJar();

  /// A jar that starts with [cookies] for [host].
  RtlPlayCookieJar.seeded(String host, Map<String, String> cookies) {
    _byHost[host] = Map.of(cookies);
  }

  /// Applies the `Set-Cookie` header of a response from [host]. Expired or emptied cookies are removed.
  void store(String host, String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.isEmpty) return;
    final cookies = _byHost.putIfAbsent(host, () => {});
    for (final raw in setCookieHeader.split(_setCookieSeparator)) {
      final parts = raw.split(';');
      final pair = parts.first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (value.isEmpty || _isExpired(parts.skip(1))) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
  }

  /// The `Cookie` header value for a request to [host], or null when there is nothing to send.
  String? header(String host) {
    final cookies = _byHost[host];
    if (cookies == null || cookies.isEmpty) return null;
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String? value(String host, String name) => _byHost[host]?[name];

  Map<String, String> cookiesOf(String host) => Map.unmodifiable(_byHost[host] ?? const {});

  static bool _isExpired(Iterable<String> attributes) {
    for (final attribute in attributes) {
      final text = attribute.trim().toLowerCase();
      if (text.startsWith('max-age=')) {
        final seconds = int.tryParse(text.substring('max-age='.length));
        if (seconds != null && seconds <= 0) return true;
      }
    }
    return false;
  }
}
