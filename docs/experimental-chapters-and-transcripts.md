# Chapters and Transcripts: Upstream and This Branch

This document describes how chapters and transcripts work in upstream Pocket Casts iOS (`Automattic/pocket-casts-ios`, `trunk`), and what the `experimental/llm-chapters-local-transcripts` branch adds on top.

For the audio fingerprinting that syncs Pocket Casts generated transcripts to playback, see [transcripts.md](transcripts.md). This document only touches on it where the branch builds on it.

---

## Part 1: Upstream

### 1.1 Two timelines

Most of what follows is about which timeline a time is on.

- **Playback timeline:** the audio file playing on the device. It can include **dynamically inserted ads (DAI)**, stitched in per listener, which shift everything after them.
- **Reference timeline:** the copy of the audio the Pocket Casts server processed to make its generated transcript and chapters. It usually has different ads, or none.

Times on the reference timeline can't be used directly for playback. Upstream bridges the two with audio fingerprinting (see [transcripts.md](transcripts.md)).

### 1.2 Chapters

`ChapterManager.parseLocalAndRemoteChapters` loads chapters from each source, then uses the first one that has any:

| Priority | Source | Origin | Timeline |
|---|---|---|---|
| 1 | Chapters embedded in the audio file (ID3 or MP4) | `.nativeMedia` | Playback |
| 2 | Podcast Index chapters (`podcast:chapters` URL in the feed) | `.podcastIndex` | Playback |
| 3 | Chapters in the episode metadata (Podlove) | `.showNotes` | Playback (publisher's audio) |
| 4 | **Server generated chapters** (AI, made from the generated transcript) | `.generated` | **Reference** |

Notes:
- `ShowInfoCoordinator.loadChapters` returns the remote sources. Generated chapters need `FeatureFlag.generatedChapters`, and are skipped when the listener turns off AI chapters (`Settings.disableAiChapters`).
- Generated chapters are on the reference timeline. Seeking to one goes through `GeneratedChapterSeeker`, which uses fingerprinting to find the matching playback position. That works from both the chapters list and the player's previous and next buttons. The chapters header shows a "generated" warning.
- Upstream never reads chapters out of the show notes text.

### 1.3 Transcripts

`TranscriptManager.loadTranscript` asks `ShowInfoCoordinator.loadTranscriptsMetadata` for the available transcripts. It then picks the best format with `TranscriptFormat.bestTranscript`:

- **Podcast transcripts** (`podcast:transcript` in the feed) **always win** over a Pocket Casts generated one when the feed has any.
- **Generated transcripts** (VTT, from `shownotes.pocketcasts.com/generated_transcripts/…`) are used only when the feed has none. They need `FeatureFlag.generatedTranscripts`, and they're behind the Plus paywall.
- Formats, in order of preference: VTT, Podcast Index JSON, SRT (all timed), then HTML and plain text (untimed). An untimed transcript parses into a model with **no cues**, so it's only text.
- `Episode.hasGeneratedTranscript` (true, false or unknown) comes from the server's podcast update, and says whether a generated transcript exists.

**Syncing with playback** (highlighting the current line, auto-scroll, tap to seek) needs `FeatureFlag.syncedTranscripts` and Plus. It works only for **generated** transcripts:
- The server publishes a reference fingerprint for the generated transcript.
- `FingerprintTimingManager` matches the device's audio against it, giving a mapping between playback time and reference time.
- Highlighting looks up the current reference time in that mapping, and only highlights while playback is on matched content, not during ads.
- Tap to seek maps the cue's reference time back to a playback time.

**Podcast transcripts never sync**, even timed ones: there's no reference fingerprint for them. Upstream shows them as static text.

### 1.4 Limitations this branch addresses

1. Episodes with no chapters in the file or feed get either server generated chapters (on the reference timeline) or no chapters at all. Show notes often contain a perfectly good chapter list, and upstream ignores it.
2. Generated chapters don't mark ads, and need fingerprinting to seek.
3. With DAI, a generated or podcast transcript's times don't match the file. Generated ones survive through fingerprinting; podcast ones are unusable for syncing.
4. Timed podcast transcripts that *do* match the file still don't sync.
5. There's no way to tell from the transcript view or the episode lists which transcript you'll get.

---

## Part 2: What this branch adds

### 2.1 Overview

```
                         ┌─────────────────────────────┐
  show notes ──────────► │ LLM: extract chapters/topics│
                         └──────────────┬──────────────┘
                 timestamps │           │ topics          │ neither
                            ▼           ▼                 ▼
                     use timestamps   place topics     make chapters
                     (re-place if     on a transcript  from a transcript
                      the file has DAI)    │                 │
                                           ▼                 ▼
                         which transcript? (2.4): podcast's (matches file)
                                                  generated (reference timeline)
                                                  on-device (when lengths differ)
                                                         │
                                                         ▼
                                        quote placement + AD chapters
```

New chapter priority in `ChapterManager.parseLocalAndRemoteChapters`:

| Priority | Source | Origin |
|---|---|---|
| 1 | Embedded in the file | `.nativeMedia` |
| 2 | Podcast Index / Podlove | `.podcastIndex` / `.showNotes` |
| 3 | **LLM chapters**: from show notes timestamps, show notes topics, or the transcript | `.llm*` (below) |
| 4 | Server generated chapters | `.generated` |

LLM chapter origins (`ChapterOrigin`):

| Origin | Meaning | Timeline |
|---|---|---|
| `.llmShowNotes` | Timestamps written in the show notes | Playback |
| `.llmTranscriptAligned` | Show notes topics placed on the generated transcript | **Reference** (seeks through fingerprinting) |
| `.llmPodcastTranscriptAligned` | Show notes topics placed on the podcast's own transcript, which matches the file | Playback |
| `.llmLocalTranscriptAligned` | Show notes topics (or show notes timestamps, re-placed because of DAI) placed on the on-device transcript | Playback |
| `.llmTranscriptGenerated` | Chapters made from a transcript alone | Playback |

`usesReferenceTimeline` is true only for `.generated` and `.llmTranscriptAligned`; those seek through `GeneratedChapterSeeker`. The chapters header shows a different AI note for each kind, and the chapter counter shows a sparkles icon for all LLM chapters.

### 2.2 LLM settings and requests

- **Settings → LLM Chapters** (`LLMChapterSettingsViewController`): the Anthropic API key, stored in the Keychain, and the model, which defaults to `claude-opus-5-5`. The screen can run a test extraction.
- **Requests** (`LLMChapterService`, an actor) use structured outputs with a JSON schema, and a server-side fallback model where supported.

| Request | Effort | Prompt version |
|---|---|---|
| Show notes extraction | Low | `showNotesPromptVersion` |
| Topic placement | Medium | `alignmentPromptVersion` |
| Transcript chapters | Medium | `generationPromptVersion` |

- **Cache** (`LLMChapterCache`): one file per episode per kind in `Application Support/PocketCasts/LLMChapters/`. The file suffixes are none (show notes), `-aligned` and `-generated`.
  - The key hashes the model, the prompt version and the inputs, so a change to any of them makes a new request.
  - Only the model's raw response is cached. Turning it into chapters happens on every load, so tuning the placement code takes effect without new requests.
  - A failed request isn't retried for 10 minutes.

### 2.3 From show notes

**Extraction** (`extractChapters`): the model reads the show notes and returns either:
- **Timestamped chapters**, when the notes have timestamps. These ignore links, so a show with several links per story doesn't get a chapter for each link.
- **An untimed topic list**, when they don't. It's taken from numbered or bulleted topics, or from a prose summary. `topicsInOrder` is false for prose, since a summary may not follow the episode's order.

**Timestamped chapters, with DAI** (`realignShowNotesChapters`): show notes timestamps are for the publisher's audio. When the file's length doesn't match the reference transcript (2.4), the file has inserted ads. The chapters are then placed again on the on-device transcript, by title, with the original timestamps as hints. This also finds the ads.

**Topics** (`alignTopics`): needs at least `minimumTopicCount` (3) topics.
1. The condensed transcript and the numbered topics go to the model. The transcript is merged into lines of about 10 seconds, each starting with `[H:MM:SS]`, with music marker lines when available.
2. For each topic, the model returns the line where it starts, plus a **start quote** of 5 to 8 words. It also lists every ad, with start and end quotes and the sponsor.
3. **Placement** turns the model's answer into chapters (all in `LLMChapterService`):
   - **`QuoteLocator`** finds each quote in the transcript text, with time interpolated within the cue. That's more precise than the 10-second line, and fixes ads that start mid-line.
   - **Order filter:** for ordered topics, it keeps the longest run of increasing start times, so one misplaced topic only costs its own chapter. This is skipped for prose topics.
   - At least half the topics must be placed, or the result is discarded.
   - The first chapter is moved to 0:00 when it starts within 30 seconds; otherwise an "Intro" chapter is added.
4. **`insertAds`** adds `AD: <sponsor>` chapters. If a topic resumes less than 30 seconds after an ad, that topic is moved to the ad's end rather than getting a sliver of a chapter. The fixed `AD:` prefix lets one chapter-filter keyword deselect every ad (2.9).
5. **`removeShortChapters`** folds topic chapters shorter than 45 seconds (30 seconds before an ad) into the previous chapter.

### 2.4 Which transcript chapters are placed on

`ChapterManager.loadAlignmentReference` picks the **reference transcript**:
1. **The podcast's own timed transcript**, the same one the transcript view shows.
2. Otherwise, **the Pocket Casts generated transcript** (`ShowInfoCoordinator.loadGeneratedTranscriptText`). For topic placement, this is only used when the server generated chapters for the episode.

`ChapterManager.transcriptForAlignment` then compares lengths (`LocalTranscripts.isOutOfSync`). If the transcript's last cue ends more than **45 seconds** from the file's length, the file has inserted ads.

| Reference | Lengths match | Lengths differ, on-device transcript cached | Lengths differ, still transcribing |
|---|---|---|---|
| Podcast's | Use it (`.llmPodcastTranscriptAligned`) | Use on-device (`.llmLocalTranscriptAligned`) | No AI chapters yet; reload when done |
| Generated | Use it (`.llmTranscriptAligned`) | Use on-device | Use generated meanwhile (fingerprint seeking); reload when done |

### 2.5 From the transcript alone

`ChapterManager.transcriptChapters` and `LLMChapterService.generateChapters` run when the show notes have no timestamps and fewer than 3 topics, or aren't usable at all. They also require:
- the episode to be at least 10 minutes long;
- AI chapters to be on;
- a transcript **on the playback timeline**: the podcast's own that matches the file, or an on-device one. When only the generated transcript is available and it matches, the server's generated chapters already come from it, so no request is made.

The model splits the episode at the main changes of topic, aiming for 4 to 10 minute chapters with specific titles, and lists the ads. Placement is the same as for topics (2.3). The music and ad rules in the prompt are shared word for word with topic placement (`transcriptRules`).

### 2.6 On-device transcripts (`podcasts/Fingerprint/LocalTranscripts.swift`)

These fix DAI: a transcript made from the listener's own file is on the playback timeline whatever ads the file has.

- **Engine:** iOS 26 `SpeechAnalyzer` with `SpeechTranscriber`, which gives a time range per run. Segments end at a sentence or after 5 seconds. Unavailable before iOS 26 (`LocalTranscripts.isSupported`).
- **When:** `LocalTranscripts.source(replacing:…)` is given a reference transcript and the file's length. It returns:
  - `.server` when the lengths match, or the file can't be transcribed;
  - `.local(model)` when a cached on-device transcript exists;
  - `.transcribing` after queuing a transcription.
- **Queue:** `LocalTranscriber` is an actor that runs one job at a time. Urgent jobs (the episode is playing, or its transcript is open) go to the front; prefetch jobs go to the back. A completion handler fires when a job finishes, which is how chapters and the transcript view reload.
- **Music detection** (`MusicDetector`, SoundAnalysis `SNClassifySoundRequest`, 1.5-second windows): this takes about 10% of the progress bar. It finds two kinds of music:
  - **Music:** jingles, intros and stings, from a smoothed confidence.
  - **Beds:** quiet music under speech, usually ads, from how many windows have some music.

  These become `[music until …]` and `[music bed under speech until …]` lines in the condensed transcript, as hints for the model. A `musicVersion` bump re-runs detection on cached transcripts.
- **Cache** (`LocalTranscriptCache`): `Application Support/PocketCasts/LocalTranscripts/<episode>.json`. Each entry is keyed by the file's identity (size and modification time), since a new download can carry different ads. `LocalTranscriptIndex` keeps an in-memory map of episodes to file identities, so the episode rows can check quickly.
- **Progress:** `LocalTranscriptProgress` tracks the queue and the current job. `LocalTranscripts.stateChangedNotification` is posted on the main queue when a job is queued, makes progress or finishes.
- **The model** (`makeModel`) groups segments into paragraphs, at pauses of 1.5 seconds or more, aiming for about 30 seconds and at most 90. It adds chapter headings at the current chapters' start times, in a larger bold font.

### 2.7 Prefetching after download (`LocalTranscriptPrefetcher`)

Started from `AppDelegate`, it observes `Constants.Notifications.episodeDownloaded`. For each download:
1. It reads the file's real length with `AVURLAsset`.
2. It loads the reference transcript (2.4) and runs `LocalTranscripts.source(…, urgent: false)`:
   - **Lengths match, podcast transcript:** precompute the chapters now.
   - **Lengths differ:** queue an on-device transcription, then precompute the chapters when it finishes.
   - **Already transcribed:** precompute the chapters.
3. To precompute chapters, it calls `ChapterManager().precomputeLLMChapters` on a throwaway `ChapterManager`. That makes and caches the AI requests without touching what's playing. It's skipped when the file or feed has its own chapters.

This only runs while the app is running. With the audio background mode, that includes the background while something is playing. A transcription that's cut short is picked up again when the episode plays.

### 2.8 Transcript view (`TranscriptViewController`)

**Source.** `TranscriptSource` decides how the view syncs:

| Source | When | Highlight and tap to seek |
|---|---|---|
| `.server` | Generated transcript | Fingerprinting (upstream behaviour) |
| `.local` | On-device transcript replacing a generated or podcast one whose length differs | Playback time directly |
| `.publisherOnFile` | Podcast's timed transcript that matches the file | Playback time directly (**new: upstream never syncs these**) |
| `.publisher` | Podcast's transcript that's untimed, or timed but doesn't match | None |

**Other behaviour:**
- When an on-device transcription finishes, a `.server` view or a timed `.publisher` view reloads with it.
- An on-device transcript is rebuilt when its chapter headings change, which happens after chapters are placed on it.
- Bookmarks on `.local` and `.publisherOnFile` use the cue's time directly. On a timed `.publisher` transcript that doesn't match, the "Bookmark" menu item is hidden, since there's no correct time to save.

**Source pill.** A capsule at the bottom says which transcript you're reading:

| Pill | Meaning |
|---|---|
| Podcast's transcript | Timed, from the feed, synced |
| Podcast's transcript, not synced to this file | Timed, from the feed, but for audio without the file's ads |
| Podcast's transcript, text only | HTML or plain text |
| Server transcript | Pocket Casts generated |
| Waiting to transcribe on device | Queued |
| Transcribing on device 42% | In progress, with a progress bar |
| On-device transcript | Made from the downloaded file |

### 2.9 Episode row indicator

`LocalTranscriptIndicatorView` is a small captions icon after the status icons. It appears in:
- `EpisodeCell`: the podcast page, playlists, downloads and the other episode lists;
- `PlayerCell`: Up Next;
- `UpNextNowPlayingCell`: the Now Playing row in Up Next.

| Icon | Meaning |
|---|---|
| Green outline | On-device transcript queued or in progress |
| Green filled | On-device transcript done |
| Blue filled | A server transcript has been downloaded: the podcast's own timed one, or the generated one |
| Blue text bubble | The podcast's own transcript has been downloaded, but it's untimed text (HTML or plain) |
| Blue outline | Generated transcript on the server, not downloaded yet (or downloading) |
| Grey filled | The server says there's no generated transcript (`hasGeneratedTranscript == false`) |
| Hidden | Unknown |

The server state comes from `ServerTranscriptStatus`:
- It reads `Episode.hasGeneratedTranscript`, so there are no network calls.
- It tracks downloads through `TranscriptsDataRetriever.loadStateChangedNotification`. The retriever's URL cache is now shared, so the status can check it.
- It checks the cache once per episode in the background, to pick up downloads from earlier launches.
- Podcast transcripts are recorded when `TranscriptManager` loads one (`transcriptLoadedNotification`), in the transcript view or by the download prefetcher. They're remembered in `UserDefaults` and take precedence over the generated state, since they're the ones the transcript view shows. A podcast transcript that hasn't been downloaded since this was added isn't known about, because finding it would mean fetching each episode's show info.

### 2.10 Chapter filter keywords

**Settings → Chapter Filter Keywords** (`ChapterFilterKeywordsViewController`). Chapters whose title contains any of the keywords are deselected automatically when an episode's chapters load. With `AD:` as a keyword, every LLM ad chapter is skipped during playback.

### 2.11 Debugging

Everything logs to `FileLog`. Useful prefixes:

| Prefix | Covers |
|---|---|
| `ChapterManager [debug]:` | Which chapter path ran, the transcript used, length checks, and the "precomputed" summary |
| `LLMChapterService:` and its debug lines | What was sent to the model and what came back, cache hits, each placement decision (`ok` / `DROP`), and the final chapters |
| `LocalTranscripts [debug]:` | Length differences, the queue, transcription timing, the app state, and the music timeline |
| `LocalTranscriptPrefetcher [debug]:` | What happened after each download |
| `TranscriptViewController [debug]:` | Which source the view picked, and reloads |

### 2.12 Files

| File | Status | Role |
|---|---|---|
| `podcasts/ChapterManager.swift` | Changed | Chapter priority, the LLM paths, transcript selection, precomputing |
| `podcasts/LLMChapterService.swift` | New | Prompts, requests, condensing, placement, ads |
| `podcasts/LLMChapterCache.swift` | New | Cache of model responses |
| `podcasts/LLMChapterSettingsViewController.swift` | New | API key and model settings |
| `podcasts/ChapterFilterKeywordsViewController.swift` | New | Keyword filter settings |
| `podcasts/Fingerprint/LocalTranscripts.swift` | New | On-device transcription, queue, music detection, cache, index |
| `podcasts/Fingerprint/LocalTranscriptPrefetcher.swift` | New | Work after a download |
| `podcasts/Fingerprint/LocalTranscriptIndicatorView.swift` | New | Episode row icon |
| `podcasts/Fingerprint/ServerTranscriptStatus.swift` | New | Generated transcript availability and download state |
| `podcasts/TranscriptViewController.swift` | Changed | Sources, syncing, the pill, chapter headings |
| `podcasts/TranscriptModel.swift` | Changed | Music ranges, the chapter heading attribute |
| `podcasts/TranscriptsDataRetriever.swift` | Changed | Shared cache, load notifications |
| `podcasts/Episode Info Coordinator/ShowInfoCoordinator.swift` | Changed | `loadGeneratedTranscriptText` |
| `podcasts/PlaybackManager.swift` | Changed | Chapter origin accessors, chapter breaks for transcripts |
| `podcasts/ChaptersHeader.swift`, `NowPlayingPlayerItemViewController+Update.swift` | Changed | AI notes, sparkles |
| `podcasts/Episode Cells/EpisodeCell.swift`, `PlayerCell.swift`, `UpNextNowPlayingCell.swift` | Changed | Row indicator |

### 2.13 Known limitations

- **API key:** LLM chapters need your own Anthropic API key, and each request is billed to it. Topic placement and transcript chapters send the whole condensed transcript, about 50k characters per hour of audio.
- **iOS 26:** on-device transcripts need iOS 26 and a downloaded (or fully stream-cached) file. They only run while the app is running.
- **Length check:** the 45-second check catches inserted ads, but not ads swapped for ones of about the same length.
- **Grey icon:** `hasGeneratedTranscript == false` can't tell "not generated yet" from "never will be".
- **Podcast transcripts in the rows:** the episode row icon only knows about a podcast transcript once one has been downloaded.
- **Web pages:** show notes pages on the web, such as a "full show notes" link, aren't followed. That was decided against as brittle; transcript chapters (2.5) cover those episodes.
