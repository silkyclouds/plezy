import '../../model/replay_ref.dart';
import 'srg_ids.dart';
import 'srg_images.dart';
import 'srg_numbering.dart';

/// The words a business unit shows to its audience.
class SrgTexts {
  final String latest;
  final String trending;
  final String mostClicked;
  final String soonExpiring;

  /// Prefix of a numbered season title, as in "Saison 3".
  final String season;

  /// Title of the season that holds the episodes without a season number.
  final String extras;

  const SrgTexts({
    required this.latest,
    required this.trending,
    required this.mostClicked,
    required this.soonExpiring,
    required this.season,
    required this.extras,
  });
}

/// Everything that differs between the SRG business units. The shared code reads this and nothing else.
class SrgUnit {
  /// Path segment of the Integration Layer and the middle part of every urn, such as `rts`.
  final String businessUnit;

  /// Provider id: the prefix of every [ReplayRef] and the logo slug.
  final String sourceId;
  final String name;

  /// Language of the programmes, and of the metadata.
  final String language;

  /// Label of the stream in the programme's own language.
  final String originalLabel;
  final SrgTexts texts;
  final SrgNumbering numbering;
  final SrgImageResizer images;

  /// Shows that hold unrelated one-off programmes. Their items are films, not episodes.
  final Set<String> filmUmbrellaShows;

  /// Title of a sign-language copy of a show. Copies duplicate the original in every list and are hidden.
  final RegExp? signedShowTitle;

  /// Title of an audio-described copy of a show. It is hidden only where the original is listed too.
  final RegExp? describedShowTitle;

  /// Topics that only hold the accessibility copies of other shows.
  final Set<String> hiddenTopics;

  /// A rights end in this year or later means "no end".
  final int noEndYear;

  SrgUnit({
    required this.businessUnit,
    required this.sourceId,
    required this.name,
    required this.language,
    required this.originalLabel,
    required this.texts,
    required this.numbering,
    required this.images,
    required this.noEndYear,
    this.filmUmbrellaShows = const {},
    this.signedShowTitle,
    this.describedShowTitle,
    this.hiddenTopics = const {},
  });

  String get videoUrnPrefix => 'urn:$businessUnit:video:';

  ReplayRef showRef(String showId) => ReplayRef(sourceId, 'show:$showId');

  ReplayRef videoRef(String videoId) => ReplayRef(sourceId, 'video:$videoId');

  ReplayRef seasonRef(String showId, SrgSeasonKey key) => ReplayRef(sourceId, 'season:$showId/$key');
}
