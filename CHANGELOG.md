# Changelog

All notable changes to Imager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Per-release detail lives in the [`release_notes/`](release_notes/) folder.

## [Unreleased]

## [0.10.0] - 2026-07-27

See [release_notes/0.10.0.md](release_notes/0.10.0.md) for details.

### Added

- Finder integration: Imager registers as an image and folder viewer, so it appears in Finder's
  "Open With" menu, opens double-clicked files, and accepts files or folders dropped on its icon.

## [0.9.2] - 2026-07-27

See [release_notes/0.9.2.md](release_notes/0.9.2.md) for details.

### Added

- File ▸ Close Image (⌘W): clears the current image and returns to the empty state, leaving the
  window open.

## [0.9.1] - 2026-07-27

See [release_notes/0.9.1.md](release_notes/0.9.1.md) for details.

### Added

- Settings ▸ General: choose how many recent files to remember (1–50). Lowering it trims the
  Open Recent list immediately.

## [0.9.0] - 2026-07-27

See [release_notes/0.9.0.md](release_notes/0.9.0.md) for details.

### Added

- Rotate and flip: Rotate Left/Right (⌘L / ⌘R), Rotate 180°, Flip Horizontal/Vertical, plus a fine
  rotation control (a degree stepper with left/right nudge) for small-angle straightening.
  Available from the Image menu and a toolbar Rotate popover. Non-destructive: Revert to Original
  restores the image and Export saves the transformed result.
- Full Screen: a toolbar button (and the standard View ▸ Enter Full Screen) to view images
  full screen.

## [0.8.0] - 2026-07-27

See [release_notes/0.8.0.md](release_notes/0.8.0.md) for details.

### Added

- Settings window (⌘,) with an Appearance pane to set the image viewing area's background:
  a solid colour (preset swatches + RGB sliders) or a checkerboard texture, with an opacity
  slider and a live preview.
- App icon.

## [0.7.0] - 2026-07-27

See [release_notes/0.7.0.md](release_notes/0.7.0.md) for details.

### Added

- Custom About window (Apple menu ▸ About Imager) showing the app icon, version and build number,
  a short description, and copyright.

## [0.6.1] - 2026-07-27

See [release_notes/0.6.1.md](release_notes/0.6.1.md) for details.

### Added

- The image info inspector now shows the file's location (a "Where" row with the folder path).
- Show in Finder (File ▸ Show in Finder, ⇧⌘R) reveals the current image in Finder;
  also available as a button in the info panel.
- Copy Path (File ▸ Copy Path, ⌥⌘C) copies the file's path to the clipboard;
  also available as a button in the info panel.

## [0.6.0] - 2026-07-27

See [release_notes/0.6.0.md](release_notes/0.6.0.md) for details.

### Added

- Export As ▸ PNG, JPEG, GIF, TIFF, or HEIC (File menu) to save a copy in a chosen format.

### Changed

- Save As… now defaults to the source image's format instead of always saving as PNG.

## [0.5.1] - 2026-07-27

See [release_notes/0.5.1.md](release_notes/0.5.1.md) for details.

### Changed

- The image info inspector now reflects the image currently shown: after cropping it reports the
  cropped dimensions and marks the image as edited, instead of always showing the source file's data.
- Saving a copy moved from Image ▸ Export… to File ▸ Save As… (⇧⌘S).

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

[Unreleased]: https://example.com/imager/compare/v0.10.0...HEAD
[0.10.0]: https://example.com/imager/releases/tag/v0.10.0
[0.9.2]: https://example.com/imager/releases/tag/v0.9.2
[0.9.1]: https://example.com/imager/releases/tag/v0.9.1
[0.9.0]: https://example.com/imager/releases/tag/v0.9.0
[0.8.0]: https://example.com/imager/releases/tag/v0.8.0
[0.7.0]: https://example.com/imager/releases/tag/v0.7.0
[0.6.1]: https://example.com/imager/releases/tag/v0.6.1
[0.6.0]: https://example.com/imager/releases/tag/v0.6.0
[0.5.1]: https://example.com/imager/releases/tag/v0.5.1
[0.5.0]: https://example.com/imager/releases/tag/v0.5.0
[0.4.0]: https://example.com/imager/releases/tag/v0.4.0
[0.3.0]: https://example.com/imager/releases/tag/v0.3.0
[0.2.0]: https://example.com/imager/releases/tag/v0.2.0
[0.1.0]: https://example.com/imager/releases/tag/v0.1.0
