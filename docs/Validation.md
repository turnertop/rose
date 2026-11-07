# macOS validation

The native implementation targets macOS 14 or later and uses Swift 5.10 with
Apple's Command Line Tools. It has no third-party packages. The current app
version is 0.1.15 (bundle build 16), approved by the owner for daily use.

## Automated checks

Run the full suite from the repository root:

```sh
./scripts/check.sh
```

The suite contains 253 checks: 83 library/layout checks, 30 image-pipeline
checks, and 140 interaction checks. They use generated images, disposable
folders, and offscreen native UI fixtures. They do not need an actual image
library or screen capture.

Coverage includes:

- Indexing: nested and empty directories, symlinks, missing/offline roots,
  external changes, cached metadata, natural sorting, search, favorites,
  collections, and recent-image ordering.
- Sidecars and state: UTF-8 Markdown, YAML tags, unrelated frontmatter,
  unchanged original image bytes, restart persistence, and retained annotations.
- Fit layout: proportional image widths, equal row heights, complete/incomplete
  rows, narrow widths, invalid dimensions, deterministic resizing, and bounded
  visible-item lookup across 10,000 synthetic layout entries.
- Imaging: real JPEG/PNG decoding, alpha, EXIF rotation, Display P3, prepared
  bitmaps, warm memory/disk caches, corruption repair, invalidation, shared
  requests, cancellation, concurrency, separate queues, and blocked disk writes.
- Browsing/search: startup without a search editor, first-character delivery,
  literal spaces during explicit editing, Backspace-to-empty, input-method
  composition, Escape, blank-area focus changes, and native control behavior.
- Keyboard/selection: forward/backward/repeated Space paging, opening and
  closing a selected image, arrow navigation, modified clicks, native card/gap
  geometry, selection/model notification, clipped controls, and window/modal
  isolation.
- Preferences/viewer: thumbnail-size bounds and persistence, saved optional
  two-finger scroll zoom, gesture direction, momentum rejection, zoom limits,
  native panning, and existing keyboard/mouse zoom controls.
- Automatic day/night (0.1.15): saved opt-in boolean, preserved manual choice,
  exact morning/evening boundaries, local offsets three and nine hours ahead,
  daylight-saving changes, real timer delivery, clock/time-zone notifications,
  wake and activation, disabling and reenabling, and no appearance publications
  during steady clock checks. Clock checks use injected dates and disposable
  preferences; they do not change the system clock. The owner tested the Settings
  feature and approved promotion; broader accessibility and device coverage
  remain separate acceptance work.

The image-pipeline checks have also passed under Thread Sanitizer. A separate
optional indexing exercise is available with `./scripts/check.sh --benchmark`.
Its 3,000 generated files measure indexing behavior, not UI frame rate or
representative photo-library performance. Large synthetic layout tests likewise
do not measure image decoding or presented frames.

## Manual coverage

Date added has generated-file coverage for folder-arrival metadata,
local-creation fallback, first discovery, cached-date retention after content
edits, old JSON indexes, persistence, stable ties, reverse ordering, and offline
roots. Optional arrival metadata is requested only for new or unmigrated paths;
sorting reads the cached index. The Mac sort starts newest first when selected.

The 0.1.14 release saves the sort field and its direction together in macOS
preferences. Fresh preference readers verify newest/oldest Date added, Name
descending, other fields, and malformed or incomplete saved choices. Startup
restores the saved direction directly; it does not reapply the interactive
newest-first default. The first-launch fallback is Name ascending.

Earlier smoke checks through 0.1.12 exercised native folder selection, nested navigation,
folder-watcher updates, offline-root recovery, selection and inspection, viewer
navigation, notes/tags/favorites, virtual collections, and relaunch persistence.
They also covered Fill/Fit/List switching, proportional Fit rows, panel toggles
and resizing, and native full screen. These are observations from development,
not a substitute for testing each release on supported macOS versions.

The latest interaction changes additionally have offscreen native/SwiftUI
coverage. Physical trackpad sensitivity, accessibility beyond keyboard routing,
visual appearance, and a complete user-driven relaunch still need a manual pass
when producing a new distributable release.

## Daily-use checkpoint — 0.1.15

The owner tested the automatic day/night preview, confirmed it works, and
approved updating the normal app and publishing the Mac and Windows builds.
The source is promoted to `main` with a new `v0.1.15` tag, preserving the older
checkpoints. The normal app is `build/Rose.app`; its predecessor is archived
locally for rollback.

The automatic appearance implementation has 253 passing Mac checks and 235
passing desktop checks. Its default is off; enabling it uses each computer's
local time for pink from 07:00 until 19:00 and dark rose overnight. Returning to
manual mode restores the saved choice. Promotion does not alter the tested
runtime behavior. Windows remains an independently versioned 0.1.3 preview;
headless checks do not replace native Windows integration acceptance.

## Daily-use checkpoint — 0.1.14

After brief manual checks of both the Date added and remembered-sort previews,
the owner approved promotion to the normal application. The source is promoted
to `main` without rewriting earlier history and tagged `v0.1.14`. The canonical
bundle is `build/Rose.app`; the earlier daily-use bundle and superseded previews
are archived locally for rollback.

The approved Swift implementation has 227 passing checks (83 library/layout,
30 image-pipeline, 114 interaction). Desktop checks passed separately with 206
checks. The promotion changes documentation and local build placement, not the
tested runtime code. License and notice resources are included in the signed
Mac bundle. Brief manual approval does not replace the remaining accessibility,
physical-device, and distribution acceptance work described above.

## Performance behavior and measurement

The collection view reuses cells. Visible cells subscribe to prepared
thumbnails; a bounded surrounding region is prefetched. Obsolete work is
cancelled and concurrent requests share jobs. Cache reads, source decoding,
and disk writes run on separate queues. During fast scrolling, prefetching
stops and source concurrency decreases. Completed thumbnails are delivered in
small batches rather than a single UI-thread burst.

Static surfaces are the default. Optional live materials, blur, and shadows
increase compositing work and should be evaluated separately from thumbnail
loading. Development comparisons favored static surfaces, but no measured
frame-rate gain or isolated cause is claimed.

An earlier screen-sharing session experienced a window-system stall. Sampling
caught the main thread waiting for a WindowServer reply in window-order
handling; the capture session was still active. This does not establish a
capture-disabled Rose defect or a verified fix. Performance investigations
should compare capture-off and capture-on operation independently and include
system memory pressure, swap activity, and compositor load.

The opt-in diagnostic launcher records display-link callback gaps and aggregate
thumbnail counters without image content, filenames, or screen capture. Those
callback gaps are diagnostic signals, not proof of presented frame rate. See
the root README for commands. Smoothness with a representative large library
has not been established by a repeatable frame-time benchmark.

## Build and implementation limits

- `scripts/build.sh` creates a native-architecture, locally ad-hoc-signed app.
  Developer ID signing, notarization, store distribution, and a sandboxed
  distribution profile are not configured. Builds are checked with the bundle
  property list and strict code-signature verification.
- Release builds remap project source/debug paths to a neutral root and strip
  debugging symbols from the bundled executable. Publication checks inspect the
  actual bundle for identifying local paths; older local development bundles
  are not automatically safe release artifacts.
- Live materials use macOS 14 APIs; this build does not call macOS 26 Liquid
  Glass APIs.
- Format support depends on installed ImageIO decoders. GIF playback is native;
  animated WebP/HEIF sequence playback is not implemented. Supported formats
  have not all been manually validated on every OS version.
- Viewer previews are downsampled to an 8,192-pixel maximum edge. Actual-size
  zoom maps original pixels to screen pixels and can exceed preview detail.
- Grid/inspector memory-cache budgets are eviction targets, not limits on the
  application's full memory footprint. Original-image decoding and viewer
  memory are separate. The disk cache is disposable.
- The local metadata index is a JSON snapshot with in-memory querying. Warm
  startup shows saved metadata and reconciles files in the background.
- External moves/renames change paths. Move an image and its Markdown sidecar
  together; virtual collections and recents do not automatically follow it.
- The note preview supports a small Markdown subset rather than a full
  CommonMark editor.
- Windows has a separate implementation and validation document. The shared
  image/sidecar format does not provide automatic device synchronization.
