import 'replay_provider.dart';

/// Country code for broadcasters that address a worldwide audience rather than one country.
const replayInternational = 'INT';

/// What settings shows about a broadcaster before any provider exists for it.
class ReplaySourceInfo {
  final String id;
  final String name;
  final ReplayPlaybackSupport support;

  /// The broadcaster has accounts and its provider implements `ReplayAccountSupport`.
  final bool supportsAccount;

  /// ISO 3166-1 country of the broadcaster, or [replayInternational].
  final String country;

  /// ISO 639-1 languages of its programmes, the main one first. Settings files the channel under the first.
  final List<String> languages;

  /// Countries the catalogue can be watched from, when the broadcaster restricts it to some. Empty means no blanket
  /// restriction: individual titles may still be blocked and the provider says so itself.
  final Set<String> availableIn;

  const ReplaySourceInfo({
    required this.id,
    required this.name,
    required this.support,
    required this.country,
    required this.languages,
    this.supportsAccount = false,
    this.availableIn = const {},
  });

  String get mainLanguage => languages.first;

  /// Whether a viewer in [viewerCountry] is outside the broadcaster's blanket restriction. An unknown location
  /// never counts as outside: nothing is greyed out on a guess.
  bool restrictsViewerIn(String? viewerCountry) =>
      viewerCountry != null && availableIn.isNotEmpty && !availableIn.contains(viewerCountry);
}
