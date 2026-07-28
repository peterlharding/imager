# Imager

A native macOS image viewer and light editor, written in SwiftUI.

Imager opens an image or a whole folder, shows you what's actually in the file, and lets you crop,
rotate, and flip without ever touching the original.
Edits live in memory until you deliberately save a copy.

## Requirements

- macOS 14.0 or later
- Xcode 15 or later to build from source

## Building

Open the project in Xcode:

```sh
open Imager.xcodeproj
```

Or build from the command line:

```sh
xcodebuild -project Imager.xcodeproj -scheme Imager -configuration Release -destination 'platform=macOS' build
```

The project is configured with a development team for local signing.
If you are building under your own Apple ID, change **Signing & Capabilities ▸ Team** in Xcode to
your own team first.

## Features

### Viewing

- Open a single image with **File ▸ Open…**, the toolbar button, or drag-and-drop.
- Open a folder with **File ▸ Open Folder…** to browse it as a set, with a QuickLook thumbnail
  sidebar and arrow-key navigation.
- Zoom and pan a large image: scroll to zoom, drag to pan, or pinch on a trackpad.
  The toolbar shows the current magnification and snaps back to fit when clicked, and you can zoom
  to fit or jump to actual size from the View menu.
- View it full screen from the toolbar or **View ▸ Enter Full Screen**.
- Recent files are remembered across launches using security-scoped bookmarks, so reopening a file
  works without re-granting access.

### Image information

The info inspector (**⌘I**) shows the file's name and location, pixel dimensions, colour model, bit
depth and profile, and any camera, EXIF and GPS metadata the file carries.

After an edit it switches to describing the image actually on screen rather than the source file's
metadata, and tells you whether those edits have been saved yet.

### Editing

- **Crop** by switching to the Select tool and dragging a marquee, then **Image ▸ Crop to Selection**.
  The selection can be moved and resized before you commit it.
- **Rotate** left, right, or 180°, plus a fine-rotation stepper for small-angle straightening.
- **Flip** horizontally or vertically.
- **Revert to Original** undoes every edit and returns to the file as it was loaded.

All editing is non-destructive.
Imager never writes to the file you opened.
To keep an edit, use **Save As…** or **Export As** to write a new file.

### Saving and exporting

- **Save As…** (**⇧⌘S**) writes a copy in the original file's format.
- **Export As** converts to PNG, JPEG, GIF, TIFF, or HEIC.

If an image has edits that have not been written out, Imager asks before letting them go, whether
you are opening something else, closing the image, moving to the next image in a folder, or
quitting the app.

### Finder integration

Imager registers as a viewer for images and folders, so it appears in Finder's "Open With" menu,
opens double-clicked files, and accepts files or folders dropped onto its icon.
It registers as an alternate opener, so it will not take over as the default handler for your images.

### Settings

**Settings ▸ General** sets how many recent files to remember, from 1 to 50.

**Settings ▸ Appearance** sets the background behind the image, either a solid colour with preset
swatches and RGB sliders, or a checkerboard, with an opacity slider and a live preview.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O | Open… |
| ⇧⌘O | Open Folder… |
| ⌘W | Close Image |
| ⇧⌘S | Save As… |
| ⇧⌘R | Show in Finder |
| ⌥⌘C | Copy Path |
| ⌘I | Show / Hide Image Info |
| ⌥⌘S | Show / Hide Thumbnails |
| ← / → | Previous / Next Image |
| ⌘= / ⌘- | Zoom In / Zoom Out |
| ⌘0 | Zoom to Fit |
| ⌘1 | Actual Size |
| ⌘K | Crop to Selection |
| ⌘L / ⌘R | Rotate Left / Rotate Right |
| ⌘, | Settings |

## Privacy and sandboxing

Imager runs in the App Sandbox with hardened runtime enabled and makes no network connections,
incoming or outgoing.

It requests only the access it needs: read-write access to files you explicitly choose through the
open and save panels, and app-scoped bookmarks so recent files keep working between launches.
Camera, Bluetooth, location, printing, USB, contacts, and calendar access are all switched off.

Opening a folder grants recursive read access to that folder, which is what makes folder browsing
work.
Opening a single file grants access to that file alone, so Imager cannot enumerate its containing
folder in that case.

## Project layout

| Path | Contents |
| --- | --- |
| `Imager/` | Application source, an Xcode filesystem-synchronized group |
| `Imager.xcodeproj` | Xcode project |
| `Info.plist` | Bundle configuration, including the Finder document types |
| `CHANGELOG.md` | All notable changes, following Keep a Changelog |
| `release_notes/` | One user-facing notes file per release |
| `RELEASING.md` | The release process |

## Versioning and releases

Imager follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The user-facing version is the `MARKETING_VERSION` build setting, bumped when a release is cut.

See [CHANGELOG.md](CHANGELOG.md) for the full history, [release_notes/](release_notes/) for the
per-release detail, and [RELEASING.md](RELEASING.md) for how a release is made.

## License

MIT.
See [LICENSE](LICENSE).
