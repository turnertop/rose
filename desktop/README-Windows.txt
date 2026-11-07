ROSE FOR WINDOWS - PREVIEW 0.1.2

LICENSE
Rose is licensed under the Apache License, Version 2.0. See LICENSE.txt and
NOTICE.txt in the extracted package. Dependencies retain their own licenses;
their attribution and terms are in THIRD-PARTY-NOTICES.txt.

1. Copy the ZIP to your Windows PC and choose "Extract All".
2. Open the extracted Rose-Windows-0.1.2-x64 folder and double-click Rose.exe.
3. Choose "Open a folder" (Ctrl+O), then select a folder of images.

Keep the whole extracted folder together. .NET is included; no SDK installation
or account is required. This preview targets 64-bit Intel/AMD Windows PCs.
It is unsigned, so Windows may show an unknown-publisher warning.

UPDATING FROM EARLIER PREVIEWS
Close the old Rose before opening this version. Extract this ZIP into its own
versioned folder; your existing folders, notes, and settings carry over.
Rose remembers maximization, normal size, and position. If upgrading from 0.1.0,
maximize once, then close and reopen to establish that saved placement. Normal
size/position are also adjusted to fit connected monitors.
Viewer fullscreen and minimized coordinates are not used as startup placement.
Window placement is stored separately in %LOCALAPPDATA%\RoseDesktop\window.json.

DATE ADDED
Choose "Date added" in the sort menu for newest additions first. The arrow
reverses to oldest first. Existing images use their local file creation date as
an estimate; later discoveries get a stable date in Rose's local index. Edits,
notes, refreshes, and restarts do not reset it. Files added while Rose is closed
are discovered at the next scan, so exact earlier download dates may be unknown.
The new fields are added automatically when older libraries are refreshed.
Recently viewed continues to mean viewing history.

Your images stay in their existing folders. Rose remembers folder connections,
settings, collections, and recently viewed images in:
    %LOCALAPPDATA%\RoseDesktop

Tags, favorites, and notes are saved beside each image as image.jpg.md.
Removing a folder connection does not remove its files. The separate Recycle Bin
action asks for confirmation before moving an image and its sidecar.

YOUR MAC AND PC ARE INDEPENDENT. There is no server or automatic synchronization.

KEYBOARD
  Type                 Start searching
  Ctrl+F               Edit search (including spaces)
  Backspace to empty   Return to browsing
  Escape               Leave search / deselect / close viewer
  Space                Page down, or open the selected image
  Shift+Space          Page up when nothing is selected
  Arrow keys           Select images / previous and next in viewer
  Ctrl+1 / 2 / 3       Fill / Fit / List
  Ctrl+B / Ctrl+I      Toggle sidebar / inspector
  Ctrl+D               Toggle favorite
  Ctrl+N               New collection with the selected images
  Ctrl+,               Settings
  Viewer + / -         Zoom
  Viewer 0 / 1         Fit / actual source-pixel size
  Viewer F             Fullscreen
  Ctrl+wheel           Zoom in viewer; drag to pan

Settings includes Pink, Dark rose, Follow system, and optional Scroll to zoom.
Image size, view, panels, appearance, and zoom gesture preference are remembered.

PREVIEW LIMITS
The release was cross-built on macOS and checked with synthetic images and
headless input/render tests. Native Windows dialogs, Explorer, Recycle Bin,
trackpad/pinch behavior, and perceived scrolling still need testing on your PC.
The bundled decoder supports JPEG, PNG, WebP, GIF and BMP. A Windows system-codec
fallback handles TIFF; that fallback still needs native-PC verification. Other
formats are accepted only when recognized; HEIC/HEIF parity with the Mac's system
codecs is not provided in this preview. Unsupported or corrupt
images are skipped, with a count in the status bar.
Very large images that cannot be decoded within the memory guard show an error.
Viewer previews are bounded to a 4096-pixel edge, while actual-size zoom uses
the original dimensions. Original images are never recompressed or replaced.

If Rose cannot launch, startup-error.log in %LOCALAPPDATA%\RoseDesktop contains
the error. The build-manifest.json and ZIP .sha256 file identify the preview.
