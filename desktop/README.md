# Rose desktop

An independent Windows-first C# / Avalonia implementation of Rose. The Swift Mac app lives at the repository root. Both use original images and `image.ext.md` annotations; there is no account, server, or synchronization. Linux remains a possible target of this codebase, not a validated release. Rose uses the [Apache License 2.0](../LICENSE), with project attribution in [NOTICE](../NOTICE). Dependencies retain their own licenses; see [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt). See the root README and `docs/Publishing.md` before publication.

The first preview provides folder connections and nested navigation, Fill/Fit/List, virtualized drawing, cancellable cached thumbnails, favorites, recents, virtual collections, tag filtering, notes, natural sorting, folder watching, image viewing, GIF playback, zoom/pan, Pink/Dark rose/system themes, persistent size and panel preferences, and the Mac app's browsing/search/Spacebar interactions with Windows shortcuts.

## Try on a PC

The packaging scripts produce `artifacts/Rose-Windows-0.1.3-x64.zip`; generated binaries are not included in the source tree. Extract that app ZIP and run `Rose.exe` from the extracted folder. Keep its neighboring files together. Close an older preview before launching the new one; local libraries and annotations carry over. The self-contained build includes .NET. The preview is unsigned. The 0.1.3 update has automated coverage but still needs a native Windows acceptance pass. See [README-Windows.txt](README-Windows.txt) for the complete instructions and remaining differences.

**Automatic day/night** is a saved Settings toggle, initially off. It uses this
computer's local clock: pink from 7 AM until 7 PM, dark rose overnight. It updates
the gallery, viewer, and open Settings window without reloading the library.
Turning it off restores the independently saved manual appearance. Clock and
time-zone changes are picked up on activation and by the next minute check.

**Date added** is an additional sort option. Selecting it starts newest first; the arrow reverses the order. Initial imports and old indexes use local file creation as an estimate. After a folder's first scan, new images record when Rose discovers them, even when their creation/modification dates were preserved from elsewhere. Those dates survive refreshes, edits, and restarts in `library.json`. When Rose is closed, discovery waits until the next scan; exact earlier download times cannot always be reconstructed. Recently viewed remains viewing history. Existing sort preference IDs remain compatible, and a saved oldest-first direction is respected on relaunch.

## Work on the source

Use .NET SDK 10 (the pinned SDK and roll-forward policy are in `global.json`). Open `Rose.slnx` in an editor or work directly inside this folder. There is one Git repository at the parent root; do not initialize another repository here. Building restores pinned packages from NuGet; the running app needs no account or sync service.

```sh
AVALONIA_TELEMETRY_OPTOUT=1 dotnet run --project src/Rose.Desktop
```

Normal local state is stored under the current user's local application-data folder, in `RoseDesktop/library.json`. Thumbnails are disposable and live in `RoseDesktop/Thumbnails`. `ROSE_DATA_DIRECTORY` redirects both for isolated development. Sidecars remain beside images; tests therefore use disposable generated fixtures exclusively.

Window placement is stored in the small `RoseDesktop/window.json` file and restored before the window is shown, independently of index loading. First launch uses a large centered window (about 90% of the usable screen, reserving space for native decorations). Later launches remember the normal bounds and maximized state. Restore Down keeps the normal bounds; closing while minimized or in viewer fullscreen preserves the preceding windowed state. Coordinates are validated against connected screens and DPI so a removed monitor cannot strand the window offscreen. Resizing/moving is saved after a short debounce and flushed on close. Pre-0.1.1 placement cannot recover an unsaved maximized state; maximize once in this update to establish the new preference.

On PowerShell, set `$env:AVALONIA_TELEMETRY_OPTOUT = '1'` before `dotnet run`. The supplied check/publish scripts opt out of both .NET CLI and Avalonia build telemetry automatically.

## Check without a native window

```sh
bash scripts/check.sh
```

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check.ps1
```

The standalone checks exercise actual image codecs, sidecar preservation and failed writes, state reload, query semantics, scan reuse and offline roots, justified layout, cancellation/deduplication/concurrency, and input routing through Avalonia's headless backend. They render synthetic UI fixtures to `artifacts/checks/`. They do not start a real app, use screen sharing, or read personal image libraries. These are functional checks, not a measurement of Windows frame rate or a replacement for a real-PC pass.

The current development pass completed **235 checks** with no build warnings or errors. See [Validation.md](Validation.md) for evidence, fixture scope, and remaining native Windows checks.

## Package for Windows

From macOS/Linux (Python 3 required for ZIP provenance and dependency notices):

```sh
bash scripts/publish-windows.sh x64
```

From Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish-windows.ps1 -Architecture x64
```

The scripts accept `arm64` for an ARM PC; that target is not validated. Outputs stay under ignored `desktop/artifacts/`. Both packaging paths include the project `LICENSE.txt`, `NOTICE.txt`, and dependency notices. The shell packager includes source-commit provenance, per-file hashes, and a ZIP checksum. The Windows script uses built-in ZIP support.

Release builds map the desktop source root to `/_/rose/desktop/` in symbols and assembly debug records, keeping the local checkout path out of those records. Debug builds retain their normal local paths for breakpoints. A caller-supplied `PathMap` takes precedence. See [Microsoft's PathMap documentation](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/advanced#pathmap).

## Implementation boundaries

- `Rose.Core`: paths, immutable asset/annotation values, preferences, safe Markdown sidecars, JSON state, scanning, queries and gallery geometry.
- `Rose.Imaging`: SkiaSharp decoding/orientation/GIF frames, a Windows GDI+ TIFF fallback, and the asynchronous thumbnail pipeline. Two thumbnail jobs maximum; canceled subscribers release work; disk cache trims from 512 MiB to 384 MiB. The gallery holds about 80 MiB of cached bitmaps and at most two in-flight gallery loads. Inspector, viewer and native decoder memory are separate from that cache budget. Originals above the 128 MiB native decode guard are rejected when the codec cannot downsample during decoding.
- `Rose.Desktop`: Avalonia controls, window and focus behavior, OS folder picker/clipboard/Explorer/Recycle Bin integration, filesystem watches, and UI-thread model coordination. Gallery layout uses metadata; one drawing surface renders only visible rows rather than creating one control or bitmap per asset.

Failed sidecar writes remain queued and prevent a silent quit. A malformed saved index is reported and kept unchanged instead of being replaced. Filesystem changes are debounced. The current preview has per-file Recycle Bin confirmation; folder disconnection and collection removal affect only app state.

## Manual Windows acceptance pass

Use your normal image folder: open, fast-scroll both directions, change Fill/Fit/List and size, toggle panels, try type-to-search and Backspace/Escape, deselect by clicking blank areas, Space-page/open/close, view and zoom a GIF, edit notes/tags/favorites, add/remove collection membership, close immediately after editing, and relaunch. Test a disposable image's Recycle Bin action, Explorer reveal, folder drag-and-drop, and live external changes. Then repeat scrolling with the full library after thumbnails have warmed. Native input feel, accessibility, color profiles and Windows shell integration require this pass before calling the Windows version equivalent to the Mac release.
