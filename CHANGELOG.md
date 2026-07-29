# Changelog

All notable changes to Imager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Per-release detail lives in the [`release_notes/`](release_notes/) folder.

## [Unreleased]

### Added

- File ▸ Edit With hands the current file to another application: GIMP, darktable, the DxO
  suite, an upscaler, or anything else installed. Applications that declare themselves editors
  of the file type are listed first, the rest sit under "All Applications", and "Other…" picks
  any application at all. Imager needs no knowledge of the tool, so anything installed later
  appears on its own.

## [0.16.0] - 2026-07-29

See [release_notes/0.16.0.md](release_notes/0.16.0.md) for details.

### Added

- "Open in Imager" Finder service for images and folders, under right-click ▸ Services. Finder
  offers no "Open With" submenu for folders whatever an app declares, so a service is the only
  way to get a right-click entry for them. It can be given a keyboard shortcut in System
  Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services.

## [0.15.0] - 2026-07-29

See [release_notes/0.15.0.md](release_notes/0.15.0.md) for details.

### Added

- Edit ▸ Copy Image (⌘C) puts the image on screen, including any edits, on the clipboard.
- Edit ▸ Paste Image (⌘V) shows an image from the clipboard. It has no file behind it, so it
  counts as unsaved straight away and closing or quitting asks before discarding it. Export As
  settles it.
- `FEATURES.md`, tracking planned and shipped features with the release each one landed in.

### Fixed

- Save As no longer fails on formats macOS can read but not write. Camera RAW (NEF, CR2, ARW,
  DNG and the rest) could be opened but never saved: Save As derived the output format from the
  source file and asked ImageIO to write RAW, which is impossible. It now falls back to PNG.

## [0.14.0] - 2026-07-29

See [release_notes/0.14.0.md](release_notes/0.14.0.md) for details.

### Added

- Multi-step undo and redo (⌘Z / ⇧⌘Z) across crop, rotate, and flip. The menu items name the
  step, e.g. "Undo Rotate". Revert to Original still discards the whole history at once.
- Folder sort order: View ▸ Sort Images By offers name, date modified, or file size, with an
  option to reverse. Name order is natural, so `photo2` sorts before `photo10`. Re-sorting keeps
  the image on screen selected, and the choice is remembered between launches.

### Fixed

- The image is no longer left oversized and off-centre after a slideshow leaves full screen. A
  fitted image now re-fits whenever the viewport changes size, including any window resize. A
  zoom level you chose yourself is still preserved across a resize.
- The image is no longer displaced when a slideshow starts from a small window on a large
  external display. The re-fit is driven by the resize itself rather than by a layout pass,
  which a window resize does not reliably trigger.

### Changed

- Edits are now recorded as a replayable list of operations rather than mutating the displayed
  image in place, so history costs no extra memory per step.
- "Unsaved edits" is now derived from the edit history rather than latched, so undoing back to
  the last saved state clears it and redoing away from that state sets it again.

## [0.13.1] - 2026-07-29

See [release_notes/0.13.1.md](release_notes/0.13.1.md) for details.

This release is packaging only. The application is unchanged from 0.13.0.

It exists because 0.13.0 was published without its signed, notarised download, and releases on
this repository are immutable: an asset cannot be added to an existing release, and deleting the
release reserves its tag name permanently rather than allowing it to be recreated. 0.13.1 is the
first release to carry a downloadable build.

## [0.13.0] - 2026-07-29

See [release_notes/0.13.0.md](release_notes/0.13.0.md) for details.

### Added

- Slideshow: run the folder being browsed as a full-screen slideshow from View ▸ Start Slideshow
  (⇧⌘F) or the toolbar. The sidebar and inspector hide while it runs and are restored afterwards,
  the display is kept awake, and leaving full screen ends it. Editing the current image stops the
  show rather than advancing away from unsaved work. Settings ▸ General sets the interval (1-60
  seconds) and whether the show repeats or stops after the last image.

- Unit test harness: an `ImagerTests` target built on Swift Testing, with a shared Xcode scheme so
  `xcodebuild test` works from a fresh clone. Suites cover the pixel transforms, the unsaved-edit
  state machine, the slideshow rules, the recent-files limit, and the export format table.

## [0.12.0] - 2026-07-28

See [release_notes/0.12.0.md](release_notes/0.12.0.md) for details.

### Changed

- README expanded from a two-line stub into full project documentation: requirements, build
  instructions, a feature overview, a keyboard shortcut reference, sandboxing and privacy notes,
  project layout, and where the release process lives.

This release changes documentation only. The application itself is unchanged from 0.11.0.

## [0.11.0] - 2026-07-28

See [release_notes/0.11.0.md](release_notes/0.11.0.md) for details.

### Added

- Unsaved-edit protection: a confirmation alert before edits are discarded, shown when opening
  another image or folder, closing the image, switching images in a folder, or quitting the app.

### Changed

- Save As and Export now tell a completed save apart from a cancelled one. A successful save
  clears the unsaved-edits state; Revert to Original stays available either way.
- The Info pane's File ▸ State reads "Edited (copy saved)" once edits have been written out,
  and "Edited (unsaved)" before that.
- Sandbox entitlements: user-selected file access is now read-write, which saving a copy requires.
  Unused capabilities have been switched off - Downloads and Pictures folder access, camera,
  Bluetooth, location, printing, and USB.

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

[Unreleased]: https://github.com/peterlharding/imager/compare/v0.16.0...HEAD
[0.16.0]: https://github.com/peterlharding/imager/releases/tag/v0.16.0
[0.15.0]: https://github.com/peterlharding/imager/releases/tag/v0.15.0
[0.14.0]: https://github.com/peterlharding/imager/releases/tag/v0.14.0
[0.13.1]: https://github.com/peterlharding/imager/releases/tag/v0.13.1
[0.13.0]: https://github.com/peterlharding/imager/releases/tag/v0.13.0
[0.12.0]: https://github.com/peterlharding/imager/releases/tag/v0.12.0
[0.11.0]: https://github.com/peterlharding/imager/releases/tag/v0.11.0
[0.10.0]: https://github.com/peterlharding/imager/releases/tag/v0.10.0
[0.9.2]: https://github.com/peterlharding/imager/releases/tag/v0.9.2
[0.9.1]: https://github.com/peterlharding/imager/releases/tag/v0.9.1
[0.9.0]: https://github.com/peterlharding/imager/releases/tag/v0.9.0
[0.8.0]: https://github.com/peterlharding/imager/releases/tag/v0.8.0
[0.7.0]: https://github.com/peterlharding/imager/releases/tag/v0.7.0
[0.6.1]: https://github.com/peterlharding/imager/releases/tag/v0.6.1
[0.6.0]: https://github.com/peterlharding/imager/releases/tag/v0.6.0
[0.5.1]: https://github.com/peterlharding/imager/releases/tag/v0.5.1
[0.5.0]: https://github.com/peterlharding/imager/releases/tag/v0.5.0
[0.4.0]: https://github.com/peterlharding/imager/releases/tag/v0.4.0
[0.3.0]: https://github.com/peterlharding/imager/releases/tag/v0.3.0
[0.2.0]: https://github.com/peterlharding/imager/releases/tag/v0.2.0
[0.1.0]: https://github.com/peterlharding/imager/releases/tag/v0.1.0
