# Imager

A native macOS image viewer and light editor, written in SwiftUI.

Imager opens an image or a whole folder, shows you what's actually in the file, and lets you crop,
rotate, and flip without ever touching the original.
Edits live in memory until you deliberately save a copy.

## Requirements

- **macOS 26 or later.**

  The build targets macOS 14.0 and the compiler enforces that, so no unavailable API is called
  and Imager may well run on earlier systems.
  It simply has not been tried on one, so anything before 26 is untested rather than unsupported.
  Highlight recovery when developing RAW does genuinely need macOS 26; it is hidden below that.

- Xcode 26 or later to build from source, since the project references APIs introduced in the
  macOS 26 SDK, guarded by availability checks.

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

## Testing

Unit tests live in `ImagerTests/` and are written with
[Swift Testing](https://developer.apple.com/documentation/testing).
Run them in Xcode with **⌘U**, or from the command line:

```sh
xcodebuild test -project Imager.xcodeproj -scheme Imager -destination 'platform=macOS'
```

The tests are hosted by the app and use `@testable import Imager`, so they can reach internal
types directly.
They cover the pixel transforms, the unsaved-edit state machine, the recent-files limit, and the
export format table.
Anything that needs a file on disk writes to a temporary directory, and anything that touches
preferences is pointed at a throwaway defaults suite, so a test run never disturbs your own
recent files or settings.

## Features

### Viewing

- Open a single image with **File ▸ Open…**, the toolbar button, or drag-and-drop.
- Open a folder with **File ▸ Open Folder…** to browse it as a set, with a QuickLook thumbnail
  sidebar and arrow-key navigation.
- Cull a set with **File ▸ Move to Trash** (**⌘⌫**), which sends the current file to the Trash and
  moves straight on to the next image.
  It does not ask first: the Trash is itself the undo, and a prompt on every image would defeat
  the point of culling.
- Order a folder by name, date modified, or file size from **View ▸ Sort Images By**, optionally
  reversed.
  Name order is natural, so `photo2` comes before `photo10`.
  Re-sorting keeps the image you are looking at on screen, and the choice is remembered.
- Group a burst, a bracket, or several tries at one shot into a **stack**, so the sidebar shows
  one row for the set rather than a run of near-identical frames.
  A stack presents a single frame - its **pick** - with a badge showing how many it holds, and a
  disclosure triangle opens it up.
  **View ▸ Stacks ▸ Stack Photos…** groups the folder by capture time; the sheet says how it would
  group before committing.
  **Set Pick** (**⌘\\**) makes the frame on screen the one the stack shows, and **Unstack** breaks
  the group up again.
  Arrow keys step past a collapsed stack, and slideshows and folder processing run on picks: the
  pictures, rather than every frame taken to get them.
  Groupings are stored in `.imager/stacks.json` beside the photos, so they survive the folder being
  moved or renamed, and are reconciled against the files present each time the folder is opened.
- Zoom and pan a large image: scroll to zoom, drag to pan, or pinch on a trackpad.
  The toolbar shows the current magnification and snaps back to fit when clicked, and you can zoom
  to fit or jump to actual size from the View menu.
- Inspect detail with the **loupe** (**⌥⌘L**): a magnifier that follows the cursor and shows one
  image pixel per point, so focus and sharpness can be judged without leaving fit-to-window.
  Its size is set in Settings ▸ General.
  Past 100% it magnifies *less* than the view, since it always shows actual pixels.
- View it full screen from the toolbar or **View ▸ Enter Full Screen**.
- Run a folder as a slideshow with **View ▸ Start Slideshow** (**⇧⌘F**) or the toolbar's play
  button.
  It goes full screen, hides the sidebar and inspector, and holds off display sleep while running.
  Escape, or leaving full screen, ends it and puts the window back as it was.
  Editing the image on screen stops the show rather than advancing away from unsaved work.
- Recent files are remembered across launches using security-scoped bookmarks, so reopening a file
  works without re-granting access.

### Image information

The inspector (**⌘I**) has two panes, switched by a segmented control at the top.

**Info** shows the file's name and location, pixel dimensions, colour model, bit depth and
profile, and any camera, EXIF and GPS metadata the file carries.

After an edit it switches to describing the image actually on screen rather than the source file's
metadata, and tells you whether those edits have been saved yet.

**Adjust** holds the tone and colour sliders described under Editing below.

### Editing

- **Crop** by switching to the Select tool and dragging a marquee, then **Image ▸ Crop to Selection**.
  The selection can be moved and resized before you commit it.
- **Rotate** left, right, or 180°, plus a fine-rotation stepper for small-angle straightening.
- **Flip** horizontally or vertically.
- **Develop camera RAW** from the sensor data, when the file is a RAW.
  The Adjust pane gains a Develop RAW section with exposure, white balance as temperature and
  tint, boost and shadow boost, and highlight recovery where the camera and system support it.
  These act on the sensor data rather than on a rendered image, which is why they can recover
  highlights and set white balance properly where the ordinary adjustments cannot.
  Reset Development returns to the reading your camera recorded, not to zero.
- **Adjust** tone and colour from the inspector's Adjust pane: exposure, highlights, shadows,
  contrast, saturation, vibrance and hue, with a Reset button.
  The image updates as you drag, and the whole drag counts as one undo step.
- **Undo** and **Redo** (**⌘Z** / **⇧⌘Z**) step back and forth through the edits one at a time.
  The menu names the step, so you can see whether you are about to undo a crop or a rotation.
- **Revert to Original** discards the whole history at once and returns to the file as it was
  loaded.
- **Save Recipe…** stores the rotation, flips and adjustments under a name, and **Apply Recipe**
  puts them onto another image.
  Applying replaces the orientation and adjustments rather than adding to them, so the result is
  the same whatever you had already done, and it counts as a single undo step.
  Crops are left out of a recipe: a crop belongs to one image's dimensions, and in practice it is
  tone you want to reuse rather than composition.

Edits are recorded as a list of operations replayed from the original image rather than as saved
copies of it, so a long history costs almost nothing in memory.

All editing is non-destructive.
Imager never writes to the file you opened.
To keep an edit, use **Save As…** or **Export As** to write a new file.

### Saving and exporting

- **Save As…** (**⇧⌘S**) writes a copy in the original file's format.
- **Export As** converts to PNG, JPEG, GIF, TIFF, or HEIC.
- **Copy Image** (**⌘C**) puts what's on screen, edits included, on the clipboard, and
  **Paste Image** (**⌘V**) opens an image from it.
  A pasted image has no file behind it, so Imager treats it as unsaved until you export it.

### Processing a whole folder

**File ▸ Process Folder…** applies a saved recipe, or the changes on screen, to every image in the
folder you are browsing.
Choose an output format - each image's own, or one format for all of them - pick a destination, and
watch it run.

Two things it will not do:

- **It never writes over an original.**
  A name already in use becomes `photo-01.png`, `photo-02.png` and so on rather than replacing
  anything.
- **It refuses the folder being processed as the destination**, so the originals are out of reach
  by construction rather than by careful naming.

A file that cannot be read or written is reported in a summary at the end rather than stopping the
run, and Cancel stops after the image in flight.

### Handing off to another editor

**File ▸ Edit With** opens the current file in another application: GIMP, darktable, the DxO
suite, an AI upscaler, or anything else installed.
Imager knows nothing about any of them, so a tool installed later appears on its own.

Applications that declare themselves editors of the file type are listed first, everything else
sits under **All Applications**, and **Other…** picks any application at all.
The split is only a hint: darktable, for one, declares itself a viewer of every image type
despite being an editor, so it appears in the second group.

Edit With opens the file **as saved on disk**, so save a copy first if you want unsaved crops or
rotations carried across.

If an image has edits that have not been written out, Imager asks before letting them go, whether
you are opening something else, closing the image, moving to the next image in a folder, or
quitting the app.

### File formats

Imager does not carry a format list of its own.
It opens whatever macOS can decode through ImageIO, which on a current system is around 60
formats: PNG, JPEG, TIFF, HEIC, GIF, BMP, WebP, PSD, and camera RAW from Nikon (NEF, NRW),
Canon (CR2, CR3), Sony (ARW), Adobe (DNG), Fujifilm, Olympus, Panasonic, Pentax, Leica,
Hasselblad and others.
RAW files open, browse, and show their EXIF metadata like any other image.

Writing is a much shorter list, because ImageIO can encode far fewer formats than it can decode.
Export As offers **PNG, JPEG, GIF, TIFF and HEIC**.

**No camera RAW format can be written**, by Imager or anything else: RAW records what a sensor
captured, and nothing re-encodes to it.
Saving a copy of a RAW file therefore produces a PNG, and Save As switches to PNG automatically
when the source format cannot be written.
Use Export As if you want a different format.

### Finder integration

Imager registers as a viewer for images and folders, so it appears in Finder's "Open With" menu,
opens double-clicked files, and accepts files or folders dropped onto its icon.
It registers as an alternate opener, so it will not take over as the default handler for your images.

Finder shows no "Open With" submenu for **folders**, whatever an app declares, so Imager also
provides an **Open in Imager** service.
Right-click a folder or an image and look under **Services**.
To give it a place of its own, or a keyboard shortcut, use
System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services.

macOS caches the services list, so a newly built copy may not appear until the app has been
launched once, or until you log out and back in.

### Settings

**Settings ▸ General** sets how many recent files to remember, from 1 to 50; the slideshow's
interval in seconds and whether it repeats after the last image; and the loupe's size, from 60 to
400 points across.

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
| ⌘⌫ | Move to Trash |
| ⌘I | Show / Hide Image Info |
| ⌥⌘S | Show / Hide Thumbnails |
| ← / → | Previous / Next Image |
| ⇧⌘F | Start / Stop Slideshow |
| ⌘\ | Set Pick (of the current stack) |
| ⌘= / ⌘- | Zoom In / Zoom Out |
| ⌘0 | Zoom to Fit |
| ⌥⌘L | Show / Hide Loupe |
| ⌘1 | Actual Size |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌘C / ⌘V | Copy Image / Paste Image |
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

Stacking a folder writes one file into it: `.imager/stacks.json`, holding the groupings as
filenames relative to the folder.
That is what lets a grouping survive the folder being moved or renamed.
Nothing else is written beside your photos, and the file is only created once you stack something.
Folders that cannot be written to - a camera card, a read-only mount, a network share - keep their
groupings in Application Support instead, keyed by path, which means they are lost if the folder
moves.

## Project layout

| Path | Contents |
| --- | --- |
| `Imager/` | Application source, an Xcode filesystem-synchronized group |
| `ImagerTests/` | Unit tests, also a filesystem-synchronized group |
| `data/` | Test images for driving the app by hand, and the script that generates them |
| `Imager.xcodeproj` | Xcode project |
| `Info.plist` | Bundle configuration, including the Finder document types |
| `CHANGELOG.md` | All notable changes, following Keep a Changelog |
| `FEATURES.md` | Planned and shipped features, with the release each landed in |
| `release_notes/` | One user-facing notes file per release |
| `RELEASING.md` | The release process |
| `CLAUDE.md` | Standing instructions for working on the project, including the invariants |

## Versioning and releases

Imager follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The user-facing version is the `MARKETING_VERSION` build setting, bumped when a release is cut.

See [CHANGELOG.md](CHANGELOG.md) for the full history, [release_notes/](release_notes/) for the
per-release detail, and [RELEASING.md](RELEASING.md) for how a release is made.

## License

MIT.
See [LICENSE](LICENSE).
