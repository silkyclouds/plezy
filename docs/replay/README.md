# Catch-up TV (Replay)

Plezy can browse and play replays from francophone broadcasters next to Plex and Jellyfin libraries. There is nothing to
host and no account to create: the catalogues come from each broadcaster's public service.

## How it is organised

```
lib/replay/
  model/        neutral types: ReplayTitle, ReplayRail, ReplayPlayback, ReplayRef
  provider/     the ReplayProvider interface, source registry
  providers/    one directory per broadcaster (api, mapper, catalogue structure, playback, images)
  client/       ReplayClient (a MediaServerClient), watch state, playback builder
  mapping/      ReplayTitle -> MediaItem, MediaHub, MediaLibrary
  text/         plain-text conversion for synopses
```

- A **source** is one broadcaster. Each enabled source is exposed as one library, so the usual Plezy screens
  (library grid, hubs, detail, search, player) work unchanged.
- Item ids are `source:nativeId`. A season of a show is `source:showId/seasonId`.
- Every show has two levels below it: seasons, then episodes. A show whose broadcaster has no seasons gets one
  synthetic season.
- **Viewing state** (resume position, watched, continue watching) is stored on the device in the shared cache table,
  because there is no account to hold it.

## Playback rules

Only unprotected streams are played. For every title a provider answers one of: playable, geoblocked, DRM-protected,
login required, expired, not yet available, or time-slot restricted, and the app shows the reason instead of a player
that fails. DRM is never bypassed, a country is never faked, and no credentials are used.

## Adding a broadcaster

1. Record the broadcaster's responses as fixtures under `test/replay/fixtures/<source>/` (trimmed, no personal data).
2. Implement `ReplayProvider` in `lib/replay/providers/<source>/`, following `providers/arte/`.
3. Add the source id to `replaySourceIds`, `replaySourceName` and `buildReplayProviders`.
4. Write `test/replay/<source>_provider_test.dart` against the fixtures, plus a live test skipped unless
   `PLEZY_LIVE_TESTS=1`.

## Credits

The endpoints each provider uses were found and checked again from scratch against the live services. The Kodi add-on
[Catch-up TV & More](https://github.com/Catch-up-TV-and-More/plugin.video.catchuptvandmore) was the starting point for
knowing which broadcasters expose which APIs. It is licensed GPL-2.0 and no code from it is used here.
