# Rose

Rose is a local image reference manager. Connect a folder, browse its images, and keep tags and notes beside the originals as Markdown. There is no import-only library, account, or sync server.

## Download

- [Windows x64 — Rose 0.1.2 preview](https://github.com/turnertop/rose/releases/download/v0.1.14/Rose-Windows-0.1.2-x64.zip)
- [macOS 14+ on Apple silicon — Rose 0.1.14](https://github.com/turnertop/rose/releases/download/v0.1.14/Rose-macOS-0.1.14-arm64.zip)
- [All release files, source code, and checksums](https://github.com/turnertop/rose/releases/tag/v0.1.14)

On Windows, choose **Extract All**, then run **Rose.exe** from the extracted
folder. Keep the neighboring files together; .NET is included. On Mac, extract
the ZIP and move **Rose.app** to Applications. Source-code ZIPs require building
the app. The Windows preview is unsigned; the Mac download is ad-hoc signed and
has not been notarized. See the release notes for validation and platform limits.

## Platforms

| Platform | Implementation | Status |
| --- | --- | --- |
| macOS 14 or later | Native SwiftUI / AppKit at the repository root | 0.1.14 |
| Windows x64 | C# / Avalonia in [`desktop/`](desktop/README.md) | 0.1.2 preview |
| Linux | Possible future target of `desktop/` | No validated release |

Each installation has its own local library and settings. Mac and Windows do not need to connect or share images. Their common file format is ordinary images plus optional `image.ext.md` sidecars.

The macOS download is **0.1.14** (build 15). Windows remains an independently
versioned **0.1.2 preview**. The `v0.1.14` release contains both downloads with
their own version numbers.

**License:** Rose's original project files are licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for project attribution and [third-party notices](desktop/THIRD-PARTY-NOTICES.txt) for dependencies, which retain their own licenses. The source and app downloads include the project license and notices; the review workflow is documented in [publication preparation](docs/Publishing.md).

## Why Rose?

Originally imagined as **Rose Quartz**, Rose takes its name from the pink quartz
gemstone. It was inspired by **Obsidian**—named after volcanic glass—and its
approach to keeping files in your own folders. We shortened the name to
**Rose**: a home for your images.

## Build and open on macOS

Use macOS 14 or later with Swift 5.10 or later and Apple's Command Line Tools. Full Xcode is optional. The build targets the machine's native architecture. The macOS app has no third-party packages.

```sh
./scripts/build.sh
./scripts/run.sh
```

The build script creates an optimized, locally ad-hoc-signed `build/Rose.app` bundle with a drawn app icon. It does not install anything into Applications. For a debug build, use `./scripts/build.sh debug`. Open `Package.swift` in Xcode if you prefer its editor and debugger. Quit Rose before rebuilding its bundle. Developer ID signing, notarization, and store distribution are not configured.

Release builds map project source paths to `/_/rose` and strip debugging symbols
from the bundled executable to remove local object-file paths. Debug builds
retain normal source paths and symbols for local development. Review the exact
source archive and release binaries before publication, as described in
[Publishing.md](docs/Publishing.md).

In Rose, choose **Open a folder** (⌘ O), or drop a folder onto the window. Click a folder to browse it; expand its chevron to see nested folders. Images stay in their existing locations.

## Build or try on Windows

See [`desktop/README.md`](desktop/README.md) for .NET SDK requirements, source commands, and packaging. The self-contained Windows ZIP includes .NET; after extracting it, run `Rose.exe` and keep its neighboring files together. The preview is unsigned. Windows-specific shortcuts, data locations, and known differences are in [`desktop/README-Windows.txt`](desktop/README-Windows.txt). A source-code ZIP is not a runnable app download.

The sections below describe the macOS implementation. The Windows preview follows the same main workflow, with platform differences documented under `desktop/`.

## Browse

- Three panes with adjustable sidebar and inspector widths. Both panels collapse independently using their toolbar buttons or View menu commands, and their visibility is remembered across launches.
- Nested folder navigation, favorites, recently viewed images, tags, and virtual collections.
- A Fill / Fit / List control switches between the original uniform cropped grid, rows of whole images in their natural proportions, and the compact list. Fit gives wide sheets wider cards and portraits narrower cards, with equal image heights within each row. The size slider controls tile size in Fill and target row height in Fit. The last row stays at a sensible size. Both the selected view and the size slider are remembered across launches.
- Search the current view by filename, relative folder path, extension, or tags. Search terms combine.
- Sort by natural filename, date added, modification date, creation date, byte size, or pixel area, in either direction. Selecting **Date added** starts with newest additions first; use the direction control for oldest first. Rose remembers the last sort and direction across folders and restarts, including an oldest-first Date added choice. A fresh installation starts with Name A–Z.
- **Include subfolders** is on initially and can be toggled in the toolbar menu or View menu.
- JPEG, PNG, WebP, HEIC/HEIF, GIF, and TIFF use the Mac's image decoders. Additional native formats are accepted when the installed decoder supports them. Corrupt and unsupported files are skipped.
- Changes made in Finder are coalesced through FSEvents. New folders and images appear without importing them. Offline connections retain the saved index and show their status in the sidebar.
- Right-click for file actions and collection membership. Removing a connected folder or virtual collection leaves the original files in place. Moving an image to the Trash requires an explicit in-app confirmation.

**Date added** means arrival in the collection, rather than the image's content modification or embedded photo date. On Mac, Rose reads the filesystem's date of addition to the current folder when available. Existing files without that date are estimated from local file creation, including when upgrading an older index. New files without arrival metadata are dated when Rose first discovers them. Windows uses local creation as an initial estimate and tracks later discoveries. Files added while Rose is closed are discovered on the next scan; Windows cannot reconstruct an exact earlier download time from missing metadata.

The resolved dates live in the local index and survive refreshes, image/note edits, and restarts. Sorting uses those cached values. Original images and sidecars are not changed to record dates. Removing a folder connection discards its index; renames and moves are treated as path changes and may establish a new addition date. **Recently viewed** continues to use viewing history.

## Look closer

Single-click selects an image and updates the inspector. Double-click, Return, or Space opens the selected image in the viewer. With the gallery focused and nothing selected, Space scrolls down one page and Shift–Space scrolls up. Rose starts with browsing focus and no search caret. Typing during browsing activates Search and enters the first character; an existing query is selected so typing starts a new search. Clicking Search, tabbing into it, or pressing ⌘ F enables ordinary text editing, including leading spaces. Backspace returns to browsing as soon as the query is empty, so Space can immediately scroll again. Escape in Search returns to browsing while preserving the query, filtered results, and image selection. Plain clicks in blank toolbar, heading, sidebar, or gallery areas return to browsing and clear image selection and its inspector. The search filter and scroll position stay in place. Controls and the inspector retain the selected image for their normal actions and editing. Other controls perform their normal actions, and other text inputs retain native typing. Escape in the gallery clears image selection. The grid remains mounted behind the viewer, preserving its scroll position and selection.

| Action | Shortcut |
| --- | --- |
| Open folder | ⌘ O |
| Search current view | ⌘ F |
| Start a new search while browsing | Type a character |
| Leave search editing, keeping the query | Escape |
| Fill / Fit / List view | ⌘ 1 / 2 / 3 |
| Select all visible images (grid focused) | ⌘ A |
| Navigate the grid | Arrow keys |
| Scroll down / up with no image selected (gallery or startup focus) | Space / ⇧ Space |
| Open selected image / close viewer | Space |
| Clear gallery selection / close viewer | Escape |
| Previous / next image in viewer | ← / → |
| Fit / actual pixel size | 0 / 1 |
| Zoom | + / −, pinch, mouse wheel, or Option + trackpad scroll |
| Pan a zoomed image | Drag; trackpad scroll when scroll-to-zoom is off |
| Native full screen from viewer | F |
| Toggle favorite | ⌘ D |
| Show in Finder | ⇧ ⌘ R |
| Show / hide sidebar | ⌃ ⌘ S |
| Show / hide inspector | ⌥ ⌘ I |
| New collection | ⇧ ⌘ N |

GIF animation uses the native animated image view. Static images are decoded off the main thread; exceptionally large viewer images are downsampled to a maximum edge of 8,192 pixels to bound decode memory. “Actual size” maps source pixels to display pixels, so a larger source can exceed the resolution of this bounded preview.

**Rose → Settings → Image Viewer → Two-finger scroll to zoom** enables upward two-finger slides to zoom in and downward slides to zoom out. It starts off, is saved across launches, and applies to an already-open viewer. With it enabled, drag to pan; pinch, + / −, and the zoom buttons remain available. Scroll momentum stops zooming when fingers lift. The setting affects the image viewer; gallery and Settings scrolling retain their normal behavior. Settings is also available from the toolbar’s ⋯ menu.

**Rose → Settings** offers Pink, Dark rose, and Follow system. Pink with static surfaces is the default. It uses opaque gradients and border highlights to retain the pink aesthetic with fewer compositing effects. Optional live glass uses native macOS 14 blur materials; this build does not call the newer macOS 26 Liquid Glass APIs.

**View → Static Surfaces** is on by default. It retains the palette, layout, and borders, replaces live materials and blurred background shapes with opaque gradients, and disables panel and window shadows. Turn it off to use live glass effects. The setting is also available in Settings and the toolbar menu, persists across launches, and applies without relaunching. Existing saved choices are respected. macOS Reduce Transparency also selects static surfaces. Settings scrolls so its full shortcut list remains accessible.

## Your files are the vault

Nothing is uploaded or copied into a private image library. Adding a connection only stores its location, a security-scoped bookmark when available, and a rebuildable metadata index.

Annotations are ordinary UTF-8 Markdown next to an image:

```text
References/
  Botanical/
    rose.jpg
    rose.jpg.md
```

```markdown
---
rose: 1
favorite: true
tags: ["botanical", "pink"]
---
## Reference

- Soft pinks and warm light.
- A useful reference for the next collection.
```

Using the full image filename (`rose.jpg.md`) distinguishes it from `rose.png.md`. Notes autosave, including pending edits when quitting. Tags and favorites create the same sidecar when changed. Original image bytes stay untouched. Existing plain Markdown bodies, common YAML list tags, and unrelated frontmatter fields are preserved. The note preview supports headings, bullets, and inline Markdown; the editor retains the original Markdown text.

Move an image and its sidecar together to carry its annotations elsewhere. Both implementations read this format. Virtual collection membership and recent history use file paths in each installation's app state, so moving a file does not preserve those references automatically.

| Data | macOS | Windows |
| --- | --- | --- |
| Library index, folder connections, collections, recents | `~/Library/Application Support/Rose/library.json` | `%LOCALAPPDATA%\RoseDesktop\library.json` |
| Generated thumbnails | `~/Library/Caches/Rose/Thumbnails` | `%LOCALAPPDATA%\RoseDesktop\Thumbnails` |
| Preferences | macOS app preferences | Library state; window placement in `RoseDesktop\window.json` |
| Notes, tags, favorites | `image.ext.md` beside each image | Same format beside each image |

Saved indexes can contain image paths, annotations, and folder permissions/bookmarks. Keep them private. They and actual image folders are not repository source files. `ROSE_DATA_DIRECTORY` redirects the app's index and cache for development; it does not redirect sidecars.

On macOS the grid and inspector have separate memory-cache budgets of 80 MiB and 20 MiB. These are NSCache eviction targets, not limits on the app's entire memory footprint. Disk caching is trimmed from 512 MiB to 384 MiB. A cached thumbnail request still checks source availability in the background. Startup uses the saved index immediately, then checks file metadata in the background. New images are published in batches during large scans.

Thumbnails are decoded into display-ready bitmaps off the main thread and displayed through Core Animation layers. Cache reads, original-image decoding, and disk writes use separate queues. Concurrent requests for the same image share work; disappearing cells cancel their subscriptions. Prefetching covers a small region around the viewport and stops during fast flings, when original-image decoding is reduced from two concurrent jobs to one. Completed images are delivered in batches of at most four, and queued cache writes retain at most eight bitmaps or 32 MiB. Existing v2 thumbnails remain reusable.

## Check the implementation

```sh
./scripts/check.sh
./scripts/check.sh --benchmark
```

The standalone Swift check runners work with Command Line Tools without requiring XCTest. They create isolated temporary folders and cover indexing, hierarchy counts, recursive navigation, natural sorting, search, sidecar round-trips and preservation, external file changes, restart persistence, and missing roots. The imaging checks also exercise real JPEG/PNG decoding, alpha and colour profiles, warm disk/memory caches, cancellation, concurrent subscribers, queue priority, and a blocked disk writer. The optional 3,000-file fixture measures indexing only; it is not a scrolling benchmark.

For optional timing logs, quit Rose and run `./scripts/run-performance.sh`, then scroll manually. The diagnostic launcher uses `build/Rose.app`; `ROSE_APP_PATH` can override it for a development build. This enables a display-link timing monitor only for that launch. It records callback gaps and aggregate thumbnail counters, without screen capture, filenames, or image content. Callback gaps are a diagnostic signal, not a measurement of presented frame rate. Inspect the summaries with:

```sh
log show --last 10m --style compact --predicate 'subsystem == "app.rose.imagevault" AND category == "scroll"'
```

For an isolated launch during development:

```sh
ROSE_DATA_DIRECTORY=/tmp/rose-sandbox swift run Rose --vault /path/to/test-images
```

The environment override redirects the index and thumbnail cache. It does not redirect Markdown sidecars, which intentionally stay beside their images; use a disposable image folder when testing annotations.

See [macOS validation](docs/Validation.md), [Windows validation](desktop/Validation.md), the [original design brief](docs/Original-Specification.md), and the [concept illustrations](docs/Design.md). The brief and illustrations describe the initial design direction; they are not a guarantee that every pictured feature is implemented. There is no cloud account, image editing, AI tagging, downloading, or Markdown knowledge-base functionality in this version.

## Repository and development

| Location | Contents |
| --- | --- |
| `Sources/`, `Tests/`, `Resources/`, `Package.swift` | Native macOS application and checks |
| `scripts/` | macOS build, check, and diagnostic scripts |
| `desktop/` | Windows implementation, checks, and packaging scripts |
| `docs/` | Design references, validation, and publication guidance |

Git tracks source, scripts, tests, documentation, and the two concept images. Build outputs and compiler caches are ignored. Use a `codex/` branch for changes and validate before review. Local publication safeguards are described in [AGENTS.md](AGENTS.md) and [Publishing.md](docs/Publishing.md).

To keep development bundles separate, set `ROSE_APP_PATH`, for example: `ROSE_APP_PATH="$PWD/build/development/Rose Dev.app" ./scripts/build.sh`. Quit Rose before switching builds; copies share the same library and preferences unless an isolated data directory is chosen.

Keep any image libraries or performance fixtures placed inside this project in `local-vaults/` or `test-vaults/`; both directories are ignored. Connected folders outside the project and Rose's Application Support and thumbnail-cache data are separate from this repository.
