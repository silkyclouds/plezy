/// Dailymotion ids come in two spellings: `x` plus five to six characters in the public API, and `k`
/// plus about eighteen on broadcasters' own sites. Both name the same video space.
final _videoId = RegExp(r'^[xk][A-Za-z0-9]{5,24}$');

final _inUrl = RegExp(r'dailymotion\.com/(?:thumbnail/video|embed/video|video)/([xk][A-Za-z0-9]{5,24})');

bool isDailymotionVideoId(String value) => _videoId.hasMatch(value);

/// The video id inside a Dailymotion thumbnail, embed or watch URL, or null.
String? dailymotionIdFromUrl(String url) => _inUrl.firstMatch(url)?.group(1);
