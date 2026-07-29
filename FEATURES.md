Feature tracker for Imager.
Items move from ToDo to Done when they ship, tagged with the release that carried them.
Per-release detail lives in [CHANGELOG.md](CHANGELOG.md) and [`release_notes/`](release_notes/).

# ToDo

## Editing

- Image adjustments: brightness, contrast, saturation.
- Drag an image out of the window to another app.
- Resize and scale an image to given dimensions.
- Straighten with a visible grid overlay.

## Files and browsing

- Move to Trash while browsing a folder, for culling a set quickly.
- Batch convert or export a whole folder.
- Name the fallback format in the Save As menu item when the source cannot be written,
  e.g. "Save As PNG…" for a RAW file.
- Recursive folder browsing, including subfolders.

## Viewing

- Slideshow transitions, and a random order option.
- Compare two images side by side.

## Project

- Port the image-handling code from the old C# program (the original goal for the app).
- Print support, which would need the printing entitlement turned back on.

## Known issues

None currently open.

# Done

## Editing

- Crop with a marquee selection, non-destructive, with Revert to Original — v0.5.0
- Rotate left, right and 180°, fine-angle rotation, and flip horizontally or vertically — v0.9.0
- Unsaved-edit protection: confirmation before edits are discarded, including on quit — v0.11.0
- Multi-step undo and redo (⌘Z / ⇧⌘Z), with the menu naming each step — v0.14.0

## Files and browsing

- Open an image via menu, toolbar, or drag-and-drop — v0.1.0
- Recent files, persisted across launches with security-scoped bookmarks — v0.2.0
- Open from Finder's "Open With" and the `open` command — v0.2.0
- Folder browsing with a thumbnail sidebar and ← / → navigation — v0.3.0
- Save As… and Export As PNG, JPEG, GIF, TIFF or HEIC — v0.6.0
- Show in Finder (⇧⌘R) and Copy Path (⌥⌘C) — v0.6.1
- Finder registration as a viewer for images and folders, including drop-on-icon — v0.10.0
- Close Image (⌘W), leaving the window open — v0.9.2
- Folder sort order by name, date modified or file size, reversible and remembered — v0.14.0
- Copy Image (⌘C) and Paste Image (⌘V), with a pasted image treated as unsaved — v0.15.0
- Save As falls back to PNG for formats macOS can read but not write, such as camera RAW — v0.15.0
- Camera RAW support, inherited from ImageIO and confirmed on Nikon NEF — v0.15.0
- "Open in Imager" Finder service for folders and images, since Finder offers no Open With
  submenu for folders — unreleased

## Viewing

- Display an image scaled to fit, with an empty state and an error alert — v0.1.0
- Image info inspector: file, image, camera (EXIF) and location (GPS) metadata — v0.2.0
- Zoom and pan: scroll to zoom, drag to pan, pinch, fit and actual size — v0.4.0
- Full screen — v0.9.0
- Full-screen slideshow of a folder, with a configurable interval and repeat — v0.13.0

## Application

- App sandbox, hardened runtime, and no network access — v0.1.0
- Custom About window — v0.7.0
- Settings window: appearance (image-area background) and general preferences — v0.8.0
- App icon — v0.8.0
- Full project documentation in the README — v0.12.0
- Unit test harness on Swift Testing, with a shared scheme so tests run from a clone — v0.13.0
- Signed, notarised, downloadable builds attached to GitHub releases — v0.13.1
- Feature tracker (this file), and file format support documented in the README — v0.15.0
