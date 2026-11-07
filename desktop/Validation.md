# Windows preview validation

The automated checks and Windows cross-build use .NET SDK 10.0.203 on macOS. The application uses Avalonia 12.1.5, SkiaSharp 3.119.4, and a pinned .NET 10.0.14 runtime for self-contained Windows packages. These toolchain details support reproducibility; they do not substitute for native Windows validation.

## Automated result

`bash scripts/check.sh` completed with **247 checks passed, zero failed groups**, and a Release build with **zero warnings and zero errors**. The standalone checks use generated temporary image folders and Avalonia's headless backend. They do not open a native app, read personal images, or capture/share the desktop.

Covered behavior:

- Viewer menu (0.1.4): actual viewport right-click opens Copy Image and Show in
  Explorer without changing zoom; commands follow navigation and retire when
  closed. Generated image pixels (including a 5,000-pixel source wider than the
  viewer preview) are copied through the in-process headless clipboard and
  remain valid after closing the viewer. Missing originals report failure and
  preserve the previous clipboard. Reveal uses a stub; real Explorer and native
  clipboard paste/exit behavior remain part of Windows acceptance.

- Release metadata: deterministic source roots normalize both compiler document
  paths and Source Link mappings in portable PDBs. A compiler PathMap alone
  does not sanitize Source Link roots when a Git remote is configured. Inspect
  the actual DLL/PDB/package bytes before publication.

- Automatic day/night (0.1.3): opt-in default and legacy JSON, saved boolean and
  independent manual choice, morning/evening boundaries, local clocks three and
  nine hours apart, startup/restart, Settings opened before loading finishes,
  the actual checkbox and disabled manual picker, timer-driven live updates in
  both main and Settings windows, restored manual appearance, and steady checks
  that do not repaint the palette or notify the library. Dates/offsets are
  injected; the system clock is never changed. Native Windows acceptance of
  this update is still pending. The live timer check runs the headless dispatcher
  event loop; merely draining queued jobs does not deliver OS timer events.
  Its simulated clock advances with elapsed time so rendering delays cannot
  leave the fixture frozen just before a boundary.

- Date added (0.1.2): initial creation-date estimates, subsequent discoveries with inherited old timestamps, stable dates across metadata reuse and content edits, old JSON and numeric sort preference compatibility, persisted dates and direction, deterministic ties, offline roots, the actual ComboBox's newest-first selection, and a first image added after an empty folder has already been scanned. The Windows date records discovery when no reliable folder-arrival timestamp is available; it is not a recovered browser-download history.

- Thumbnail cancellation during sort changes: obsolete requests are detached before cancellation because cancellation can synchronously finish a waiting load. A blocked-decoder gallery fixture exercises viewport changes, reverse ordering, suspend, and resume with queued requests. This also protects viewer suspension from dictionary changes during cancellation.

- Window placement (0.1.1): large centered first launch applied before Show, persisted normal bounds and maximization, real headless close/reopen cycles, preserved Restore Down bounds, minimized-coordinate rejection, fullscreen-to-windowed continuity, separate small-file storage, negative monitor coordinates, disconnected-monitor recovery, oversized bounds, high-DPI coordinates, changed DPI, small working areas, missing screens, and malformed placement data. Native Windows window-manager transitions still require the PC pass below.

- Markdown sidecars: UTF-8 tags, quoted and block-list tags, CRLF, exact note bodies, unknown frontmatter preservation, extension-specific names, unchanged original image bytes, atomic writing, coalesced edits, and retained pending writes after failure.
- Local state: separate libraries in separate state directories, restart preferences, collections/recents, snapshots, invalid numeric preferences, malformed JSON, unsupported schemas, and malformed asset entries.
- Queries: natural numeric ordering, directory-boundary containment, recursive/direct folder selection, favorites, collections, recent ordering, tag matching, combined search terms, descending order, and empty results.
- Layout: Fill/Fit/List for 1,057 aspect-ratio fixtures, finite contained frames, bounded visible-item enumeration, keyboard row navigation, hit testing, final-row behavior, and invalid/extreme input.
- Imaging: actual JPEG/PNG/WebP decoding, bounded previews, EXIF rotation, transparency, corrupt images, GIF frame compositing, timing, and looping. Two additional TIFF cases are conditional on Windows and were **not executed in the macOS check run**.
- Indexing/cache: unchanged metadata reuse, independent sidecar refresh, new files, empty/nested folders, offline roots, cancellation, symlink loops, shared thumbnail requests, cancellation of one subscriber, warm disk reuse, stale/missing originals, burst concurrency, invalid cache recovery, and released subscriptions.
- Headless UI: startup browsing focus, Space paging, first-character search, Backspace to empty, explicit search spaces, Escape, blank toolbar/heading deselection, select-all, view/panel shortcuts, notes/favorites, viewer open/close and zoom, source-pixel sizing, held Space repeat, dark appearance, persistent size, bounded gallery cache, rendering, empty-search continuity, overlapping roots, edit/refresh races, and typing while startup finishes.

The UI fixture contains 12 generated real images and 1,057 synthetic cached metadata records. Pink and dark renders are generated under ignored `artifacts/checks/`. This exercises large-gallery geometry and interaction but does **not** establish real-world Windows frame rate, actual Windows memory use, or large-library indexing throughput.

## Windows package

`scripts/publish-windows.sh x64` cross-builds the self-contained Windows executable and verifies the PE architecture of the app host, .NET runtime, SkiaSharp, HarfBuzz, and ANGLE libraries. It checks required managed dependencies and self-contained runtime configuration, includes dependency notices and instructions, generates per-file hashes/source provenance, verifies ZIP CRCs, and emits a SHA-256 checksum. The final source commit is recorded in `build-manifest.json` inside the package.

Release builds use a neutral source-root mapping for compiler-generated paths in symbols and managed assembly debug records. Package review must also inspect generated metadata and binaries for identifying local paths; a source-only scan is insufficient.

Native decoder imports inspected in the pinned x64 Skia/HarfBuzz/ANGLE binaries reference Windows system DLLs rather than a separately installed VC++ runtime. The packaging checks do not execute the resulting application on Windows.

Preview 0.1.0 received an initial manual Windows launch and browsing smoke test. Later placement, Date added, automatic appearance, and viewer-menu updates have headless coverage. The current package is `Rose-Windows-0.1.4-x64.zip`; its native Windows acceptance checks remain pending.

## Remaining acceptance work

Run the extracted package on the target PC. Verify native folder picking, Explorer reveal, Recycle Bin confirmation on a disposable file, clipboard, drag-and-drop, folder-watch notifications, DPI/monitor behavior, precision-trackpad/pinch feel, and real scrolling with a representative large image library. The Windows TIFF fallback also needs this pass.

HEIC/HEIF support is not equivalent to the Mac's system codecs. Unsupported images are skipped with a status count. Static viewer previews are bounded to a 4,096-pixel edge; formats requiring more than the native 128 MiB decode guard show a preview error. Large GIFs and unusual color profiles require further Windows validation. Accessibility beyond keyboard navigation and selection announcements needs a dedicated review before public release.

The preview is unsigned. It is an independent local application with no sync server or connection to the Mac library. Linux is not a validated release. Rose is licensed under Apache-2.0; the source and future packages include the project license and attribution alongside third-party notices. Packages built before this license addition must be rebuilt before publication.
