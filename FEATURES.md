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

## v0.19.0 — folder housekeeping — **shipped**

- Move to Trash while browsing a folder.
- Name the fallback format in the Save As menu item. *(The only actual fix in the plan.)*

## v0.20.0 — edit recipes — **shipped**

Save the changes made to an image under a name, and apply them to another image.
Built as planned, with one thing the plan had not accounted for: making applying a recipe a single
undo step meant moving undo and redo from popping individual edits to holding snapshots of the
whole edit list, since an action that *rewrites* the history cannot be undone by removing one
entry. An `[ImageEdit]` is a handful of numbers, so the snapshots cost nothing, and all 141
existing tests passed against the new model unchanged.

**The simplification that shapes it.** A recipe looks like an editable list of steps, but the
existing semantics collapse it: only the last `.adjust` applies, so a recipe's tonal content is
exactly one `Adjustments` value, and rotate/flip compose into one of eight orientations.
A recipe is therefore **orientation + adjustments**, which is why there is no step-editor UI —
editing a recipe's tone is what the Adjust pane already does.
The general edit list is still what gets *stored*, since that costs nothing and leaves room for
resize and straighten later.

**Crop is excluded.** A crop rect is in pixel coordinates of one particular image, so it cannot
transfer meaningfully to a photo of another size, and in practice you batch tone rather than
composition. Applying a recipe therefore leaves any crop alone.
Normalised 0-1 crops would work and could be added later; they were rejected for v0.20.0 because
they change existing crop semantics for little gain.

**Applying a recipe replaces orientation and adjustments, and keeps crops.** Predictable whatever
was already done to the image, and it falls out as a single undo step, which appending every edit
would not.

**Storage.** One JSON file per recipe under Application Support inside the sandbox container,
which needs no user interaction to write. Files rather than `UserDefaults` so recipes can later be
exported or shared. Each file carries a format version.

`Codable` synthesis was checked before planning around it: Swift generates it for `ImageEdit` with
readable JSON, and a custom `init(from:)` on `Adjustments` that defaults missing values to neutral
means a recipe saved today still loads once new sliders exist.

Build order: `Codable` on `ImageEdit` and `Adjustments` → `Recipe` (name, version, edits, date) →
`RecipeStore` (list/save/delete, directory injected so tests use a temp folder) →
`ImageModel.applyRecipe(_:)` → Image menu: Save Recipe… with a name sheet, Apply Recipe ▸ list,
Delete Recipe ▸ list.

Watch for: recipe names becoming filenames, so they need sanitising or an index; and applying a
recipe to an image of a very different aspect ratio, where the orientation may not be what was
wanted.

## v0.21.0 — batch processing — **shipped**

Apply a recipe, or the edits currently on screen, to every image in a folder.
Built as planned. One thing the plan had not foreseen: batch initially wrote `.jpeg` where Export As
writes `.jpg`, because it took the extension from `preferredFilenameExtension` rather than from
`ImageFormat`. The same image getting a different name depending on which route wrote it is the
sort of inconsistency nobody would think to look for, so `BatchFormat.fileExtension(for:)` now
follows the existing rules and a test pins every format against Export As.

**Two safety properties, which drove the decisions.**

*Never write over an original.* A batch that replaces someone's photos is the one failure that
cannot be undone. So the destination is chosen explicitly, **the source folder is refused as a
destination** — which makes touching the originals structurally impossible rather than merely
unlikely — and a name that already exists is **numbered rather than overwritten**, as Finder does.
Numbering was chosen over skipping because a second run after changing the recipe would otherwise
appear to do nothing.

*One bad file does not stop the run.* An unreadable image or a failed write is collected and
reported in a summary — "38 of 40 written, 2 failed" — rather than aborting midway.

**Shape.** Source is the folder currently being browsed, so it reuses existing state, respects the
sort order on screen, and needs no second picker; the command is disabled when no folder is open.
What gets applied is a saved recipe or the current `recipeEdits`, the latter being nearly free and
the obvious thing to want. Format is either the source's own, reusing the existing PNG fallback so
RAW input yields PNG, or an explicit choice from the export formats.
Progress is a sheet with a bar, the current filename and Cancel; work runs off the main thread and
cancellation is checked between images, which at roughly 50 ms each is responsive enough.
Sequential rather than parallel, to keep memory bounded on a folder of 24 MP files.

**Build order.** `BatchProcessor.process(...)` and the naming/collision logic first: both are pure
and fully testable headlessly, and both are where the bugs would be. Then `BatchRunner`
(`@Observable`) for progress and cancellation, then the sheet and File ▸ Process Folder….

**Will need a real run.** Writing to the destination is a sandbox operation, and that is the third
feature in a row where the suite cannot see the thing most likely to break. The destination comes
from an open panel so it should carry write access, but treat that as unverified until it has been
run. See [[imager-sandbox-access]] in memory.

## v0.22.0 — RAW development

`CIRAWFilter`, rendering from sensor data rather than the demosaiced image that `NSImage` returns.
The prerequisite for white balance being worth having, and the only real answer to 8-bit banding.
Planned in detail; **needs a sample RAW file before building** — see the end of this entry.

**The architectural crux.** RAW settings cannot be an `ImageEdit`. An `ImageEdit` transforms an
image; RAW settings *produce* one, from the URL, before any image exists, so `apply(to:)` has
nothing to act on.
They therefore live as separate model state — and the snapshot-based undo introduced in v0.20.0
pays for itself here: extending `HistoryEntry` to carry the RAW settings alongside the edit list
gives RAW parameters undo, redo and single-step grouping for free. Had undo still popped individual
edits, this would have needed a second, parallel mechanism.

`rebuildImage()` gains one stage at the front: develop the base (RAW settings for a RAW file, the
loaded bitmap otherwise) → replay the geometry edits → apply the final adjustment.

**Controls for v1**, chosen as the ones that are genuinely impossible after demosaicing:
`exposure`, `neutralTemperature` and `neutralTint`, `boostAmount` and `boostShadowAmount`, and the
`highlightRecoveryEnabled` toggle — the last being the thing the shipped adjustments provably
cannot do.
Noise reduction, detail, sharpness, moire and lens correction are deliberately left for later:
useful, but refinements rather than RAW-only capabilities.

**Every control must be gated on its `Supported` flag.** `CIRAWFilter` exposes nine of them —
`highlightRecoverySupported`, `localToneMapSupported`, `sharpnessSupported`,
`lensCorrectionSupported` and so on — because support varies by camera and decoder. The pane has to
ask per file and adapt rather than showing a fixed set of sliders. This was found by dumping the
property list rather than assumed from the documentation.

**Performance will need work here, unlike adjustments.** Demosaicing is far heavier than the 12 ms
colour pipeline, so live sliders will need `draftModeEnabled`, `scaleFactor`, or both — the proxy
approach held in reserve for v0.18.0 and not needed there. Measure before choosing.

**Recipes and batch both carry RAW settings.** Recipes gain optional RAW settings, ignored when
applied to a non-RAW image. `BatchProcessor` currently opens files with `NSImage(contentsOf:)`, so
it needs the RAW path too — otherwise batching a folder of NEFs would silently use the default
rendering, and developing one frame then applying it to the shoot is the main reason to want any of
this.

**Fallback.** `CIRAWFilter` can fail on an unsupported camera, so the `NSImage` path has to remain
as a fallback rather than leaving the file unopenable.

**Blocked on a sample RAW.** Development time cannot be measured, `CIRAWFilter` cannot be verified,
and the `Supported` flags cannot be checked without a real file. Every plan in this sequence has
been corrected by measurement, so this one should not be built blind. A NEF is around 25 MB, too
large to commit; RAW extensions are gitignored, so a local copy under `data/` works.

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
- Normalised crops in recipes, stored as 0-1 fractions so a crop can transfer between images of
  different sizes. Excluded from v0.20.0 deliberately; see the Plan entry.
- New adjustments should be added as `ImageEdit` cases so they join undo and recipes for free.

## Files and browsing

- Batch over a folder other than the one being browsed, or over a selection rather than all of it.
- Parallel batch processing. Sequential was chosen to keep memory bounded on folders of 24 MP
  files; revisit only if a real batch turns out to be slower than the disk.
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
- Edit recipes: save the rotation, flips and adjustments under a name and apply them to another
  image, from the Image menu — unreleased

  One JSON file per recipe in Application Support, versioned, decoded tolerantly so a recipe
  saved today still loads once more adjustments exist. Applying replaces orientation and
  adjustments and keeps crops, which makes the result independent of what was already done and
  gives a single undo step. Crops are excluded from recipes.

  An action that lands on the history already in force records no undo step. Without that, rotating
  by hand and applying a recipe that rotates the same way needed ⌘Z twice: the first restored a
  state indistinguishable from the current one. Found by testing the app, with the suite green.

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
- Move to Trash (⌘⌫) while browsing, advancing to the next image — v0.19.0
- Batch processing: File ▸ Process Folder… applies a recipe or the current edits to a whole
  folder — v0.21.0

  Never overwrites: collisions become `photo-01.png`. The folder being processed is refused as a
  destination, so the originals are unreachable by construction rather than by correct naming.
  Failures are summarised rather than stopping the run. Sequential, off the main thread,
  cancellable between images.

  No confirmation, deliberately: the Trash is the undo, Finder's ⌘⌫ does not prompt either, and
  asking on every image would defeat the culling this exists for. It does not ask about unsaved
  edits either, since the file itself is being thrown away.
  The trash operation is injected into `ImageModel` so tests do not fill the real Trash.
- Save As names the format when it differs from the source, e.g. "Save As PNG…" for a RAW
  file — v0.19.0

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
