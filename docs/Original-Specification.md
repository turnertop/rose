# Image Vault — macOS App Specification

This is the original design brief, retained as background. Current behavior,
platform support, and validation limits are documented in the root README and
the implementation-specific validation documents. Proposed features below may
not be implemented in the current releases.

**Version:** 1.0  
**Platform:** macOS (Apple Silicon first)  
**Product type:** Local-first image reference manager  
**Design direction:** Original three-column mockup with refined Apple Liquid Glass styling and pink accents.

## 1. Product Overview

Image Vault is a lightweight macOS application for browsing, organizing, and viewing large collections of locally stored reference images.

The application replaces the repetitive workflow of opening images through Finder and Quick Look.

Users connect existing folders once. Image Vault automatically displays their images as visual grids, maintains their directory structure, and allows rapid navigation without individually importing files.

**Core principle:** The user's filesystem is the source of truth. Image Vault is a visual interface over those files, not a separate image-storage system.

## 2. Main Window

The application uses three primary columns.

### A. Left Sidebar — Folder Navigation

Displays:

- All Images
- Favorites
- Recently Viewed
- Collections
- Connected folders and nested subfolders
- Add Folder button

**Behavior:**

1. User selects Add Folder.
2. A native macOS folder picker appears.
3. User selects an existing directory.
4. The application remembers the folder and obtains persistent access through macOS permissions.
5. The sidebar displays that folder and its subfolders.
6. Clicking a folder immediately displays its images in the central grid.
7. Newly added or removed images automatically appear or disappear when the folder changes.

The user never needs to manually select or reimport individual images.

Folders may be removed from the sidebar without deleting their contents.

### B. Center — Image Grid

The primary content area.

Features:

- Responsive thumbnail grid
- Adjustable thumbnail size
- Smooth scrolling through thousands of images
- Automatic thumbnail generation and caching
- Image counts
- Sorting by filename, date, size, or dimensions
- Ascending and descending sorting
- Search within the selected folder
- Optional recursive browsing of subfolders
- Grid and compact list display modes

**Interactions:**

- Single-click: Select image and update preview
- Double-click: Open fullscreen viewer
- Arrow keys: Move image selection
- Space: Open or close enlarged viewer
- Command + A: Select all visible images
- Right-click: Open contextual actions
- Drag and drop: Add folders or images where appropriate

The grid preserves its scroll position when entering and exiting the fullscreen viewer.

### C. Right Panel — Image Preview

Displays the currently selected image.

Features:

- Large image preview
- Previous and next navigation
- Original filename
- Image dimensions
- File format and size
- Favorite toggle
- Show in Finder
- Copy image or file path
- Optional user-defined tags
- Optional notes associated with the image

The panel can be collapsed to provide additional room for the grid.

Notes and tags are secondary functionality, not the app's central purpose.

## 3. Fullscreen Image Viewer

A distraction-free viewing experience.

**Requirements:**

- Display images at maximum practical size without cropping by default.
- Fit to window, actual-size, and zoom modes.
- Navigate with left and right arrow keys.
- Use mouse wheel or trackpad to zoom when appropriate.
- Pan enlarged images.
- Provide a minimal overlay showing filename and navigation controls.
- Press Escape to return to the original grid and selection.
- Support fullscreen and regular-window viewing.

Navigation should feel immediate, without reopening individual files through Finder.

## 4. Folder and File Management

### Local-first architecture

- Existing images remain in their original folders.
- No automatic copying into an internal library.
- No mandatory cloud account.
- No mandatory internet connectivity.
- No automatic renaming or relocation.
- Original images remain unmodified unless the user explicitly authorizes an operation.

### Folder synchronization

The application observes connected directories for filesystem changes.

When images are added, deleted, renamed, or moved externally, the image grid and index update accordingly.

If a folder becomes unavailable, the application displays a clear offline or missing-folder state without discarding the user's saved organization.

### Supported formats

Initial support should include:

- JPEG / JPG
- PNG
- WebP
- HEIC / HEIF
- GIF
- TIFF

Additional formats may be supported when compatible macOS decoders are available.

Animated images should animate in the viewer without requiring custom playback controls for the initial release.

## 5. Visual Design

### Overall direction

Retain the first mockup's functional three-column layout, rather than removing useful navigation to achieve minimalism.

Use a refined Apple-inspired aesthetic with:

- Pink-tinted Liquid Glass
- Translucent, softly blurred sidebar and toolbar surfaces
- Subtle glossy highlights
- Rounded panels and controls
- Restrained shadows
- Clean typography
- Spacious but efficient spacing
- Highly visible image content

**Important:** The interface must not compete visually with the reference images. Large pink gradients and decorative elements should not dominate the application.

### Interface behavior

- Selected folder receives a clear highlight.
- Selected image receives a visible outline.
- Controls provide hover and pressed feedback.
- Side panels can be resized.
- Toolbar stays compact.
- Interface adapts smoothly to window resizing.
- Supports macOS light and dark appearance, with pink accents retained where appropriate.

The design should resemble a polished native macOS image manager, not a Markdown editor or document-management application.

## 6. Search and Organization

### Search

Search by:

- Filename
- Folder
- File extension
- User-defined tags (when available)

### Organization

The existing Finder folder hierarchy remains the primary organizational method.

Additional virtual organization may include:

- Favorites
- Recently Viewed
- User-defined collections
- Tags

Virtual collections must reference existing image files rather than duplicate them.

## 7. Performance Requirements

The application should remain responsive with large image libraries.

### Engineering requirements

- Load thumbnails lazily.
- Cache thumbnails on disk.
- Decode images away from the main UI thread.
- Reuse visible grid cells through virtualization.
- Avoid loading every full-resolution image into memory.
- Cancel image-loading work when items scroll out of view.
- Limit memory usage through bounded caches.
- Incrementally index newly connected folders.
- Recover gracefully from missing or corrupted image files.

Initial targets:

- Smooth grid navigation for folders containing thousands of images.
- No full application freeze during indexing.
- No unnecessary reindexing on every launch.
- Large images should not prevent scrolling or navigation.

These are engineering targets, not claims of measured performance.

## 8. Technical Architecture

**Recommended stack:**

- Language: Swift
- Interface: SwiftUI, with AppKit where needed for macOS-specific behavior or high-performance grid handling
- Image loading: ImageIO and native macOS image frameworks
- File monitoring: FSEvents
- Metadata/index: SQLite or equivalent local persistent storage
- Folder permissions: Security-scoped bookmarks where required
- Thumbnail cache: Application-managed local cache

The image index stores paths, identifiers, metadata, and user annotations. It does not replace the original files.

If the original image is changed or removed, the cache must not be treated as an authoritative copy.

## 9. Primary User Journey

**First launch**

1. Open Image Vault.
2. See a clean empty state with an Add Folder action.
3. Select an existing Pinterest reference folder.
4. The app discovers images and subfolders.
5. The sidebar populates automatically.
6. The central grid displays images.
7. Select any thumbnail to preview it.
8. Double-click to view it at a larger size.
9. Navigate with the arrow keys.
10. Press Escape to return to the same grid position.

**Subsequent launches**

The previously connected folders appear automatically. The user can select a folder immediately without reimporting anything.

## 10. Explicit Non-Goals for Version 1.0

The initial release will not attempt to be:

- An Obsidian replacement
- A Markdown knowledge-base editor
- A full Photoshop-style image editor
- A Pinterest downloader or scraper
- A cloud storage service
- An AI-powered image generation platform
- A mandatory database-based digital asset management system

AI tagging, visual similarity search, contact sheets, and advanced collections can be considered later.

## 11. Acceptance Criteria

The initial release is complete when:

- [ ] A user can connect an existing image folder.
- [ ] The app remembers connected folders across launches.
- [ ] Sidebar navigation reflects the folder hierarchy.
- [ ] Selecting a folder displays its images without manual importing.
- [ ] The grid supports adjustable thumbnail sizes.
- [ ] Selecting an image displays a large preview.
- [ ] Arrow-key navigation works reliably.
- [ ] Fullscreen viewing and returning to the grid preserve selection and scroll position.
- [ ] Adding images through Finder updates the library.
- [ ] Original image files are never silently modified.
- [ ] Thumbnail loading remains responsive on large folders.
- [ ] The three-column UI supports resizing and collapsing the preview.
- [ ] The pink Liquid Glass design remains readable, consistent, and secondary to the images.

## 12. Product Philosophy

**Open a folder once. Browse its images forever.**

The application should make a large local image collection feel as convenient to explore as a modern image gallery, while preserving the simplicity, portability, and ownership of ordinary Finder folders.
