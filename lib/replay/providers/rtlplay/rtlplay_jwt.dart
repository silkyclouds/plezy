import 'dart:convert';

/// The `exp` claim of a JWT as a time, or null when [token] is not a JWT or has no usable expiry.
/// The signature is not checked: the value only schedules a refresh.
DateTime? rtlPlayJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = claims is Map<String, dynamic> ? claims['exp'] : null;
    return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true) : null;
  } on FormatException {
    return null;
  }
}
