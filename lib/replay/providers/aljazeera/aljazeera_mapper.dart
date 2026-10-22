import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'aljazeera_ids.dart';
import 'aljazeera_images.dart';
import 'aljazeera_text.dart';

/// The Brightcove video id of a post, or null when the post has no video of its own.
///
/// Programmes such as Witness publish most films on YouTube only and leave this empty. Those posts cannot be
/// played here and are never offered.
String? aljazeeraVideoId(Map<String, dynamic> post) {
  final id = (post['video'] as Map?)?['id'];
  return id is String && id.trim().isNotEmpty ? id.trim() : null;
}

/// A programme entry of the section lists as a show, or null for an entry without a usable slug.
ReplayTitle? aljazeeraShow(Map<String, dynamic> programme) {
  final slug = _slugOf(programme['link']);
  final title = aljazeeraText(programme['title'] as String?);
  if (slug == null || title.isEmpty) return null;
  final image = aljazeeraUploadUrl((programme['featuredImage'] as Map?)?['sourceUrl']);
  final section = programme['primaryCategoryTermName'] as String?;
  return ReplayTitle(
    ref: AljazeeraId.show(slug).ref,
    kind: ReplayKind.show,
    title: title,
    summary: _summary(programme, title),
    posterUrl: image,
    backdropUrl: image,
    genres: section == null || section.isEmpty ? const [] : [section],
    airDate: aljazeeraDate(programme['date']),
  );
}

/// The calendar year of a programme, which the site does not number any other way, as a season.
ReplayTitle aljazeeraSeason(ReplayTitle show, int year, {int? episodeCount}) => ReplayTitle(
  ref: AljazeeraId.season(show.ref.nativeId, year).ref,
  kind: ReplayKind.season,
  title: '$year',
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: year,
  childCount: episodeCount,
  showRef: show.ref,
  showTitle: show.title,
);

/// A programme episode, or null when the post has no Brightcove video.
///
/// [programme] and [showTitle] fill in what the post does not carry itself. [number] is the position of
/// the episode in its year, known only to the caller that read the whole year.
ReplayTitle? aljazeeraEpisode(Map<String, dynamic> post, {String? programme, String? showTitle, int? number}) {
  final video = aljazeeraVideoId(post);
  final parent = _parentOf(post);
  final slug = parent?.slug ?? programme;
  if (video == null || slug == null) return null;

  final aired = aljazeeraDate(post['date']);
  final show = AljazeeraId.show(slug).ref;
  return _base(post, video, aired).build(
    ref: AljazeeraId.episode(slug, video).ref,
    kind: ReplayKind.episode,
    seasonNumber: aired?.year,
    episodeNumber: number,
    showRef: show,
    showTitle: parent?.name ?? showTitle,
    seasonRef: aired == null ? null : AljazeeraId.season(slug, aired.year).ref,
  );
}

/// A short news clip, or null when the post has no Brightcove video.
ReplayTitle? aljazeeraClip(Map<String, dynamic> post) {
  final video = aljazeeraVideoId(post);
  if (video == null) return null;
  return _base(post, video, aljazeeraDate(post['date'])).build(ref: AljazeeraId.clip(video).ref, kind: ReplayKind.clip);
}

/// Episodes of a page of posts, without the unplayable ones and without repeats.
List<ReplayTitle> aljazeeraEpisodes(Iterable<Map<String, dynamic>> posts, {String? programme, String? showTitle}) {
  final seen = <Object>{};
  return [
    for (final post in posts)
      if (aljazeeraEpisode(post, programme: programme, showTitle: showTitle) case final title? when seen.add(title.ref))
        title,
  ];
}

List<ReplayTitle> aljazeeraClips(Iterable<Map<String, dynamic>> posts) {
  final seen = <Object>{};
  return [
    for (final post in posts)
      if (aljazeeraClip(post) case final title? when seen.add(title.ref)) title,
  ];
}

/// Fields shared by episodes and clips; the caller sets what identifies the title.
_Draft _base(Map<String, dynamic> post, String video, DateTime? aired) {
  final title = aljazeeraText(post['title'] as String?);
  final image = aljazeeraUploadUrl((post['featuredImage'] as Map?)?['sourceUrl']);
  return _Draft(
    title: title.isEmpty ? video : title,
    summary: _summary(post, title),
    image: image,
    seconds: aljazeeraDurationSeconds((post['video'] as Map?)?['duration'] as String?),
    aired: aired,
  );
}

class _Draft {
  final String title;
  final String? summary;
  final String? image;
  final int? seconds;
  final DateTime? aired;

  const _Draft({required this.title, this.summary, this.image, this.seconds, this.aired});

  ReplayTitle build({
    required ReplayRef ref,
    required ReplayKind kind,
    int? seasonNumber,
    int? episodeNumber,
    ReplayRef? showRef,
    String? showTitle,
    ReplayRef? seasonRef,
  }) => ReplayTitle(
    ref: ref,
    kind: kind,
    title: title,
    summary: summary,
    posterUrl: image,
    backdropUrl: image,
    durationSeconds: seconds,
    year: aired?.year,
    airDate: aired,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    showRef: showRef,
    showTitle: showTitle,
    seasonRef: seasonRef,
  );
}

({String slug, String? name})? _parentOf(Map<String, dynamic> post) {
  final programs = post['programs'];
  if (programs is! List) return null;
  for (final p in programs.whereType<Map<String, dynamic>>()) {
    final slug = p['slug'];
    if (slug is String && slug.isNotEmpty) {
      final name = aljazeeraText(p['name'] as String?);
      return (slug: slug, name: name.isEmpty ? null : name);
    }
  }
  return null;
}

String? _slugOf(Object? link) {
  if (link is! String) return null;
  final segments = link.split('/').where((s) => s.isNotEmpty).toList();
  return segments.length == 2 && segments.first == 'video' ? segments.last : null;
}

/// The synopsis, unless it only repeats the title, which news clips do.
String? _summary(Map<String, dynamic> item, String title) {
  final text = aljazeeraText(item['excerpt'] as String?);
  return text.isEmpty || text == title ? null : text;
}

/// An episode or clip described by its Brightcove record, used when a title is opened by its id alone.
///
/// [showTitle] is the programme name the caller looked up from the programme list.
ReplayTitle? aljazeeraTitleFromVideo(Map<String, dynamic> video, AljazeeraId id, {String? showTitle}) {
  final name = aljazeeraText(video['name'] as String?);
  if (name.isEmpty || id.video == null) return null;
  final aired = aljazeeraDate(video['published_at']);
  final summary = aljazeeraText((video['long_description'] ?? video['description']) as String?);
  final poster = video['poster'] as String?;
  final milliseconds = (video['duration'] as num?)?.toInt();
  final episode = id.isEpisode;
  return ReplayTitle(
    ref: id.ref,
    kind: episode ? ReplayKind.episode : ReplayKind.clip,
    title: name,
    summary: summary.isEmpty || summary == name ? null : summary,
    posterUrl: poster,
    backdropUrl: poster,
    durationSeconds: milliseconds == null ? null : (milliseconds / 1000).round(),
    year: aired?.year,
    airDate: aired,
    seasonNumber: episode ? aired?.year : null,
    showRef: episode ? id.showRef : null,
    showTitle: episode ? showTitle : null,
    seasonRef: episode && aired != null ? AljazeeraId.season(id.programme!, aired.year).ref : null,
  );
}
