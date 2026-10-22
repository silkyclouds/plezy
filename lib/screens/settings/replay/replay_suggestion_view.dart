import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../replay/suggestions/replay_suggestion_settings.dart';

/// A language name inside a sentence: lower case in French ("français suivi"), as listed elsewhere.
String replayLanguageInSentence(String code, String locale) {
  final name = replayLanguageName(code, locale);
  return locale == 'fr' ? name.toLowerCase() : name;
}

/// The languages spoken by [infos], ordered by their name in [locale].
List<String> languagesOfChannels(Iterable<ReplaySourceInfo> infos, String locale) {
  final codes = {for (final info in infos) ...info.languages};
  return codes.toList()..sort((a, b) => replayLanguageName(a, locale).compareTo(replayLanguageName(b, locale)));
}

/// The languages the home screen follows: the viewer's own pick, else the automatic set.
Set<String> followedLanguages(ReplaySuggestionSettings settings, Set<String> automatic) =>
    settings.languages.isEmpty ? automatic : settings.languages;

/// The "Activées · français, néerlandais" line of the entry row.
String suggestionsEntrySummary({
  required ReplaySuggestionSettings settings,
  required Set<String> automatic,
  required Iterable<ReplaySourceInfo> enabledChannels,
  required String locale,
}) {
  if (!settings.enabled) return t.replay.suggestions.entryOff;
  final followed = followedLanguages(settings, automatic);
  final shown = [
    for (final code in languagesOfChannels(enabledChannels, locale))
      if (followed.contains(code)) replayLanguageInSentence(code, locale),
  ];
  if (shown.isEmpty) return t.replay.suggestions.entryOnPlain;
  return t.replay.suggestions.entryOn(languages: shown.join(', '));
}

enum ReplayChannelReason { ruleOn, ruleOff, userOn, userOff }

/// Whether a channel gets rows on the home screen, and why.
class ReplayChannelStance {
  final bool offered;
  final ReplayChannelReason reason;

  /// The language that decided it, for the two rule reasons.
  final String language;

  const ReplayChannelStance({required this.offered, required this.reason, required this.language});

  String line(String locale) => switch (reason) {
    ReplayChannelReason.ruleOn => t.replay.suggestions.reasonRuleOn(language: replayLanguageInSentence(language, locale)),
    ReplayChannelReason.ruleOff => t.replay.suggestions.reasonRuleOff(
      language: replayLanguageInSentence(language, locale),
    ),
    ReplayChannelReason.userOn => t.replay.suggestions.reasonUserOn,
    ReplayChannelReason.userOff => t.replay.suggestions.reasonUserOff,
  };
}

ReplayChannelStance channelStance(ReplaySuggestionSettings settings, ReplaySourceInfo info, Set<String> automatic) {
  final chosen = settings.channels[info.id];
  if (chosen != null) {
    return ReplayChannelStance(
      offered: chosen,
      reason: chosen ? ReplayChannelReason.userOn : ReplayChannelReason.userOff,
      language: info.mainLanguage,
    );
  }
  final followed = followedLanguages(settings, automatic);
  final match = info.languages.where(followed.contains).firstOrNull;
  return ReplayChannelStance(
    offered: match != null,
    reason: match != null ? ReplayChannelReason.ruleOn : ReplayChannelReason.ruleOff,
    language: match ?? info.mainLanguage,
  );
}

/// The languages after a viewer taps the chip of [code]: always a manual list, built from what is followed now.
/// Returns null when the tap would leave no language, which the settings cannot express (empty means automatic).
Set<String>? toggledLanguages(ReplaySuggestionSettings settings, Set<String> automatic, String code) {
  final next = {...followedLanguages(settings, automatic)};
  if (!next.remove(code)) next.add(code);
  return next.isEmpty ? null : next;
}
