import '../../media/media_hub.dart';

/// Whether catch-up cards in [hub] carry their channel's logo.
///
/// Rows that mix catch-up titles with the rest of the library (Continue Watching, recently added) need it to say where
/// a card comes from. A row that belongs to one channel, such as a home suggestion or a channel page row, already names
/// the channel in its title.
bool replayHubShowsChannelLogo(MediaHub hub) => !(hub.identifier?.startsWith('replay.') ?? false);
