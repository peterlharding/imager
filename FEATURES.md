Feature tracker for Imager.
Items move from ToDo to Done when they ship, tagged with the release that carried them.
Per-release detail lives in [CHANGELOG.md](CHANGELOG.md) and [`release_notes/`](release_notes/).

Plan below says *when*; ToDo says *what and why*.

# Plan

The next few releases, in order. Provisional: nothing is fixed until it is built, and anything
here can be resequenced.

Numbering follows [RELEASING.md](RELEASING.md), where a new feature is a MINOR bump and PATCH is
for backward-compatible fixes only. That is why these are minor releases rather than 0.18.x: they
all carry features.

## v0.19.0 — folder housekeeping — **done, unreleased**

- Move to Trash while browsing a folder.
- Name the fallback format in the Save As menu item. *(The only actual fix in the plan.)*

## v0.20.0 — edit recipes

Save the sequence of changes made to an image, edit it, and re-apply it.
Half-built already: `ImageEdit` is the recorded workflow, so this is persistence plus a UI.

## v0.21.0 — batch processing

Apply a recipe, or a format conversion, across a whole folder.
**Depends on v0.20.0** — a batch is a recipe applied many times, so recipes have to exist first.

## v0.22.0 — RAW development

`CIRAWFilter`, rendering from sensor data rather than the demosaiced image.
Independent of the three above, and the largest of them.
Also the prerequisite for white balance being worth having, and the only real answer to 8-bit
banding.

# ToDo

## Editing

- RAW development via `CIRAWFilter(imageURL:)`, exposing exposure, boost and neutral
  temperature/tint rendered from sensor data.
  Distinct from the shipped adjustments, which act on the already-demosaiced 8-bit rendering
  that `NSImage` hands back, so they cannot recover highlights the way darktable or DxO do.
- White balance, curves, and per-channel colour, once the adjustment pipeline has earned it.
- Drag an image out of the window to another app.
- Resize and scale an image to given dimensions.
- Straighten with a visible grid overlay.
- Edit recipes: record the sequence of changes made to an image, let it be edited, save it, and
  apply it to a whole folder.
  The `ImageEdit` history added in v0.14.0 is already this, minus persistence: making it
  `Codable` gives saved recipes, and applying one to a folder is then a loop.
  New adjustments should be added as `ImageEdit` cases so they join undo and recipes for free.

## Files and browsing

- Batch processing: apply an edit recipe, or a format conversion, to every image in a folder,
  writing the results somewhere else rather than over the originals.
  Needs recipes first, since a batch is a recipe applied many times.
  The work beyond that is a destination folder, a naming rule, progress, and cancellation.
- Recursive folder browsing, including subfolders.

## Viewing

- Slideshow transitions, and a random order option.
- Compare two images side by side.

## Project

- Port the image-handling code from the old C# program (the original goal for the app).
- Print support, which would need the printing entitlement turned back on.

## Integration with other tools

The tools below - darktable, the DxO suite, GIMP, AI upscalers such as Topaz, and denoisers -
all want the same thing from Imager: hand the image I am looking at to that application.
That is one feature, not five, and it needs no per-tool knowledge.
"Edit With…" (shipped, see Done) covers every one of them, including tools installed later.

What remains is the part that genuinely differs per tool:

- Favourite editors: let a few chosen applications be pinned to the top of Edit With and
  remembered.
  This matters because the menu cannot rank them automatically: darktable declares itself a
  `Viewer` of every image type rather than an `Editor`, and DxO is likely the same, so they sort
  into "All Applications" alongside browsers and chat apps.
- Hand over the *edited* image rather than the file on disk, by exporting to a temporary file
  first. Today Edit With opens the file as saved, so unsaved crops or rotations are not carried
  across.
- Notice a sidecar next to a RAW file and report it in the info inspector: `.xmp` for darktable,
  `.dop` for DxO. Needs folder access, so it works while browsing a folder rather than after
  opening a single file.
- Reload automatically when a file changes on disk, so a round trip through an external editor
  shows up without reopening.
- Watch a tool's export folder and offer to open what appears.

Not achievable, and deliberately not listed as a goal: showing darktable's or DxO's edits inside
Imager.
Both are non-destructive and render through their own pipelines, so only they can display their
own work.

## Known issues

None currently open.

# Done

## Editing

- Crop with a marquee selection, non-destructive, with Revert to Original — v0.5.0
- Rotate left, right and 180°, fine-angle rotation, and flip horizontally or vertically — v0.9.0
- Unsaved-edit protection: confirmation before edits are discarded, including on quit — v0.11.0
- Multi-step undo and redo (⌘Z / ⇧⌘Z), with the menu naming each step — v0.14.0
- Image adjustments in an Adjust inspector pane: exposure, highlights, shadows, contrast,
  saturation, vibrance and hue, with Reset — v0.18.0

  Built as planned. One `ImageEdit.adjust` holds all seven values, so a drag is one undo step,
  and only the last adjustment applies during replay, keeping any history to one filter pass.
  Rendered through Core Image in a linear colour space.

  Two planning assumptions turned out not to hold, both checked rather than assumed:
  `CIHighlightShadowAdjust` works fine at its default `inputRadius` of 0 (shadows 16 → 47 on a
  gradient), and the five-pass pipeline runs in about 12 ms at 24 MP, so the proxy rendering and
  geometry caching held in reserve were not needed.

  **Do not add 16-bit rendering to reduce banding.** It was measured against
  `data/adjustment-test.png` and makes no difference at all: a +3 EV push leaves the full ramp
  with 100 distinct levels and a largest jump of 9, identically at `RGBA8` and `RGBAh` working
  formats. The banding comes from the source being 8-bit, and output precision cannot invent
  levels the file never had. The only real fix is a higher bit depth source, which is the RAW
  development item in ToDo.

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
  submenu for folders — v0.16.0
- File ▸ Edit With: hand the current file to any other application, with declared editors listed
  first and everything else under "All Applications" — v0.17.0
- Move to Trash (⌘⌫) while browsing, advancing to the next image — unreleased

  No confirmation, deliberately: the Trash is the undo, Finder's ⌘⌫ does not prompt either, and
  asking on every image would defeat the culling this exists for. It does not ask about unsaved
  edits either, since the file itself is being thrown away.
  The trash operation is injected into `ImageModel` so tests do not fill the real Trash.
- Save As names the format when it differs from the source, e.g. "Save As PNG…" for a RAW
  file — unreleased

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
