# Changelog

All notable changes to Imager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Per-release detail lives in the [`release_notes/`](release_notes/) folder.

## [Unreleased]

## [0.5.0] - 2026-07-27

See [release_notes/0.5.0.md](release_notes/0.5.0.md) for details.

### Added

- Crop: a Select tool (toolbar Pan/Select toggle) to draw a crop rectangle over the image
  (create, move, and resize via handles), then Crop to Selection (⌘K).
- Revert to Original restores the uncropped image; cropping is non-destructive in the view.
- Export… (⇧⌘E) saves the current (possibly cropped) image to a new PNG/JPEG/TIFF file.
  The original file is never modified.

## [0.4.0] - 2026-07-26

See [release_notes/0.4.0.md](release_notes/0.4.0.md) for details.

### Added

- Zoom and pan: scroll to zoom (centered at the cursor), drag to pan, and pinch to zoom.
  Zoom In (⌘=), Zoom Out (⌘-), Zoom to Fit (⌘0), and Actual Size / 100% (⌘1), plus toolbar controls
  showing the current zoom percentage. Images open zoomed to fit (small images shown at 100%).

## [0.3.0] - 2026-07-26

See [release_notes/0.3.0.md](release_notes/0.3.0.md) for details.

### Added

- Folder browsing: File ▸ Open Folder… (⇧⌘O) loads a folder's images into a thumbnail
  sidebar (QuickLook thumbnails, Finder-style name sort). Select a thumbnail to view it.
- Navigate images with ← / → (View ▸ Previous/Next Image) or the sidebar.
- Toggle the thumbnail sidebar from the toolbar or View ▸ Show/Hide Thumbnails (⌥⌘S).
- Dragging a folder onto the window browses it.

## [0.2.0] - 2026-07-26

See [release_notes/0.2.0.md](release_notes/0.2.0.md) for details.

### Added

- Image info inspector showing file, image, camera (EXIF), and location (GPS) metadata.
  Toggle it with the toolbar button or View ▸ Show Image Info (⌘I).
- Recent files: File ▸ Open Recent lists recently opened images and reopens them,
  persisting access across launches via security-scoped bookmarks. Includes Clear Menu.
- Open images from Finder ("Open With…") or the `open` command; opened files are added to recents.

### Fixed

- Opening an image after the window was closed now reopens a window to display it.
  The app uses a single-window scene, stays running when the window is closed, and reopens on Dock click.

## [0.1.0] - 2026-07-26

Initial release.
See [release_notes/0.1.0.md](release_notes/0.1.0.md) for details.

### Added

- macOS app scaffold (SwiftUI, App Sandbox enabled).
- Open an image via the File ▸ Open… menu (⌘O), a toolbar button, or drag-and-drop.
- Display the opened image scaled to fit while preserving aspect ratio.
- Empty state prompting how to open an image, and an error alert for unreadable files.

[Unreleased]: https://example.com/imager/compare/v0.5.0...HEAD
[0.5.0]: https://example.com/imager/releases/tag/v0.5.0
[0.4.0]: https://example.com/imager/releases/tag/v0.4.0
[0.3.0]: https://example.com/imager/releases/tag/v0.3.0
[0.2.0]: https://example.com/imager/releases/tag/v0.2.0
[0.1.0]: https://example.com/imager/releases/tag/v0.1.0
