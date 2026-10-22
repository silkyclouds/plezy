/// Source id of the French edition.
const france24SourceId = 'france24';

/// Source id of the English edition.
const france24EnglishSourceId = 'france24en';

/// One language tree of the France 24 catalogue: which tree to read and how to label it.
///
/// The broadcaster serves French, English, Spanish and Arabic trees from one root document. Each tree has
/// its own catalogue addresses and the same structure, so a language is only a code and its wording.
class France24Language {
  /// Source id and prefix of every ref of this edition.
  final String sourceId;
  final String name;

  /// Language code of the tree in the root document (`FR`, `EN`).
  final String code;

  /// ISO 639-1 code of the content.
  final String language;

  final String programmesCategoryTitle;
  final String videosCategoryTitle;
  final String latestVideosTitle;
  final String latestEditionsTitle;
  final String allProgrammesTitle;

  /// Programmes that are listed by the broadcaster but have nothing this app can play.
  final Set<String> hiddenProgrammes;

  const France24Language({
    required this.sourceId,
    required this.name,
    required this.code,
    required this.language,
    required this.programmesCategoryTitle,
    required this.videosCategoryTitle,
    required this.latestVideosTitle,
    required this.latestEditionsTitle,
    required this.allProgrammesTitle,
    this.hiddenProgrammes = const {},
  });

  static const french = France24Language(
    sourceId: france24SourceId,
    name: 'France 24',
    code: 'FR',
    language: 'fr',
    programmesCategoryTitle: 'Émissions',
    videosCategoryTitle: 'Vidéos',
    latestVideosTitle: 'Dernières vidéos',
    latestEditionsTitle: 'Dernières éditions',
    allProgrammesTitle: 'Toutes les émissions',
  );

  /// "The Observers" (`WB5103037-F24-EN-20101011`) links to YouTube only: every file address is empty.
  static const english = France24Language(
    sourceId: france24EnglishSourceId,
    name: 'France 24 English',
    code: 'EN',
    language: 'en',
    programmesCategoryTitle: 'Shows',
    videosCategoryTitle: 'Videos',
    latestVideosTitle: 'Latest videos',
    latestEditionsTitle: 'Latest editions',
    allProgrammesTitle: 'All shows',
    hiddenProgrammes: {'WB5103037-F24-EN-20101011'},
  );
}
