Feature tracker for Imager.
Items move from ToDo to Done when they ship, tagged with the release that carried them.
Per-release detail lives in [CHANGELOG.md](CHANGELOG.md) and [`release_notes/`](release_notes/).

Plan below says *when*; ToDo says *what and why*.

# Plan

**v1.0.0 shipped on 2026-07-30**, marking the point at which Imager is finished enough to rely on.
The recipe file format, the preference keys and the behaviour described in the README are from now
on treated as things not to break without a major version.

Below is the sequence that led there. The next few releases, in order. Provisional: nothing is
fixed until it is built, and anything here can be resequenced.

Numbering follows [RELEASING.md](RELEASING.md), where a new feature is a MINOR bump and PATCH is
for backward-compatible fixes only. That is why these are minor releases rather than 0.18.x: they
all carry features.

## v1.2.0 — stacks — **shipped**

Group a burst or a bracket so the set collapses to a single pick in the sidebar, expanding when the
rest is wanted. From Aperture. The point is that a shoot of 400 frames where 300 are near-duplicates
browses as the hundred pictures actually taken, without deleting the alternatives.

Built as planned. Four things the plan had not accounted for:

- **EXIF capture time is not precise enough on its own.** `DateTimeOriginal` holds whole seconds,
  which is exactly the case a burst breaks: four frames in one second look simultaneous, so a burst
  either groups at every threshold or at none. Cameras that shoot bursts write
  `SubsecTimeOriginal` alongside, and reading it is what makes the half-second threshold mean
  anything. The plan's "nearly free" was right about the grouping and wrong about the reading.
- **Selection had to stay indexed on the whole folder.** Making `selectionIndex` count visible rows
  instead would have touched display, sorting, saving and trashing. Keeping it on `folderImages`
  and deriving `visibleImages` and `pickImages` left all four untouched; what changed is only what
  is shown and what stepping moves through.
- **Collapsing a stack can hide the image on screen**, which would leave the sidebar highlighting a
  row that is not there. Collapsing, trashing and auto-stacking all move the selection to the pick.
- **Gaps are measured against the previous frame, not the first of the group.** Otherwise holding
  the shutter down splits into a new stack every time the burst outruns the threshold. Not in the
  plan because the plan said "a sort and a scan", which hides the choice.

The test data needed rebuilding too: everything in `data/` was PNG, which carries no EXIF, so
stacking was invisible to all of it. `data/stacks` is ten JPEGs laid out like a shoot.

**Move to Trash** ended up more general than planned - it takes whatever is on screen rather than
only the pick, then reconciles - which keeps the same guarantee (never destroys anything not
visible) and also works when a stack is expanded.

**Storage, settled.** A `.imager/` directory beside the photos, holding `stacks.json`.

- Named for the app rather than the feature, so it can hold future per-folder state without
  breeding dot-directories, and so it will not collide with another tool's `.stacks`.
- **Filenames stored relative to the folder.** This is what makes the whole choice worthwhile: the
  grouping survives the folder being moved or renamed, which is the only reason to prefer this over
  Application Support. Absolute paths would throw that away and leave the harder option with no
  advantage.
- `imageURLs(in:)` already passes `.skipsHiddenFiles`, so the directory is invisible to browsing,
  slideshows and batch with no change.
- Versioned and tolerantly decoded, as recipes are.

**When the folder cannot be written** — a camera card, a read-only mount, a network share — fall
back to Application Support keyed by the folder's path. Silently losing the grouping is the worst
outcome, so the fallback matters more than its tidiness.

**Reconcile on load.** Drop names that no longer exist, since files get deleted in Finder, and drop
any stack left with fewer than two members.

**Auto-stacking by capture time** is the feature that makes it worth having, and is nearly free:
EXIF capture time is already extracted for the info inspector, so grouping is a sort and a scan.
Aperture had a slider — set it to two seconds and every burst becomes a stack — which is worth
copying.

**How stacks meet what already exists**, settled. Stacking is a photographic idea rather than a
file-management one, so the features that present a folder follow the picks:

- **A slideshow shows picks only** — the hundred pictures taken, not the four hundred frames. Every
  frame stays reachable by expanding the stack.
- **Process Folder runs on picks only**, for the same reason and so a batch does not spend minutes
  developing frames that were stacked away.
- **Move to Trash takes only the pick**, promoting the next frame to replace it. Deliberately the
  conservative one: it never destroys anything not visible at the time, at the cost of several
  presses to bin a whole bad burst. A whole-stack command can follow later if that proves annoying.
  *(Shipped as "takes whatever is on screen" — see above.)*

**Will need a real run.** Writing into a browsed folder is something Imager has never done. The
entitlement is `user-selected.read-write` so it should be permitted, but that is reasoning, not
evidence, and this is the fifth feature to run through sandbox territory the test suite cannot see.

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

## v0.22.0 — RAW development — **shipped**

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

**Every control must be gated on its `Supported` flag.** `CIRAWFilter` exposes nine of them, because
support varies by camera and decoder. Confirmed on `DSC_4927.NEF`: highlight recovery, sharpness,
detail, contrast, luminance and colour noise reduction and moire reduction are all supported, while
**local tone map and lens correction are not** — two of nine unavailable on a mainstream Nikon file.
A fixed set of sliders would therefore show controls that silently do nothing.
Found by dumping the property list rather than trusting the documentation.

**Performance: hold the filter instance.** Measured against `data/DSC_4927.NEF`, 7360×4912 (36 MP).
The plan originally assumed `draftModeEnabled` and `scaleFactor` were the answer. They are not.

| | |
| --- | --- |
| New `CIRAWFilter` per render, full size | 366-557 ms |
| New filter per render, any reduced scale | 86-94 ms — a floor, unchanged from ¼ to ⅛ |
| `draftModeEnabled` at full size | 230-423 ms, barely better |
| **One instance reused, ¼ scale** | **first 150 ms, then 7 ms** |
| One instance reused, full size | ~160 ms every time, never warms up |

The decode is cached *inside a filter instance*, so the whole game is keeping one alive per open
file. A fresh filter per render — the shape `ImageAdjuster` uses, and the obvious thing to copy —
costs 86 ms at best and would make live RAW sliders feel impossible.

`scaleFactor` can be switched on a live instance without losing the cache: ¼ → full → ¼ returns to
6-9 ms. So one instance suffices; no double buffering. Drag at reduced scale for 7 ms a tick, then
render full size once on release for ~160 ms.

**RAW defaults are not neutral, and differ per file.** This file opens with
`baselineExposure` 0.3, `boostAmount` 1.0, `boostShadowAmount` 0.9, `neutralTemperature` 3175 K,
`neutralTint` 1.31, `shadowBias` 3.0 — the decoder's own reading of the shot.
So `RawSettings` cannot have fixed neutral constants the way `Adjustments` does, and Reset must mean
"back to what the decoder chose for *this* file" rather than back to zero. Values are stored
absolutely, which is also what makes them meaningful in a recipe applied to another frame.

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

- Curves and per-channel colour, once the adjustment pipeline has earned it.
- More RAW controls: noise reduction, detail, sharpness, moire, lens correction. All exposed by
  `CIRAWFilter` and all gated on their own `Supported` flags; left out of v0.22.0 as refinements
  rather than things only RAW can do.
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

## Settings

- **Editable keyboard shortcuts.**
  Let the shortcut on a menu command be changed and remembered, rather than being fixed at build
  time.

  The motivating case is concrete: Set Pick shipped on ⌘\ in v1.2.0 and never reached Imager,
  because another installed application had claimed it.
  That is not a bug that can be fixed once.
  Which shortcuts are already taken depends on what else is installed, so no set of defaults is
  right for everybody, and the only durable answer is to let the shortcut be changed without a
  rebuild.

  **Check the built-in route before building anything.**
  macOS already does this: System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ App Shortcuts adds a
  shortcut to any menu item, matched on its exact title, for a chosen app or for all of them.
  It costs no code and it already works today.
  If it does, this becomes a README paragraph rather than a settings pane, and the honest version
  of the feature might be a Settings button that opens that panel.
  Worth ten minutes with the actual app before designing anything.

  If an in-app version is still wanted:

  - The stored form is a character plus a modifier set, not a `KeyboardShortcut` — that is not
    `Codable`. Reconstructing one is straightforward; what needs checking is whether SwiftUI
    re-reads `.keyboardShortcut` when the stored value changes, or whether the menu has to be
    rebuilt for it to take.
  - Conflicts *within* Imager can be detected and refused. Conflicts with other applications
    cannot be seen at all, so the failure the user meets is a shortcut that silently does nothing,
    exactly as ⌘\ did. The interface should assume that and make reassignment easy rather than try
    to prevent it.
  - Menu enablement and shortcuts are among the things the test suite cannot see, so this needs a
    run of the real app to confirm anything.

## Project

- **Verify on an older macOS.** The build targets 14.0, but Imager has only ever been run on 26.x,
  so the README claims 26 rather than 14. The compiler guarantees no unavailable API is called;
  what is unverified is runtime behaviour, and this app leans on SwiftUI in places that have moved
  between releases — `.inspector`, sheets raised from menu commands, `Slider(onEditingChanged:)`,
  `@Observable` inside `Commands`.
  A macOS 15 laptop is expected to be available for this; widen the README once it passes.
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
- RAW development from sensor data: exposure, temperature, tint, boost, shadow boost and
  highlight recovery, carried by recipes and batch — v0.22.0

  Built as planned, and the plan's own measurements held. One `RawDeveloper` per open file is the
  whole performance story. RAW settings ride in the undo snapshots rather than being an
  `ImageEdit`, which gave undo, redo and per-drag grouping for free.

  Two things the plan missed. `isHighlightRecoveryEnabled` needs macOS 26 while Imager targets 14,
  found by the compiler rather than by the probe script — a standalone `swift` script compiles
  against the host OS, not the app's deployment target, so probing that way proves less than it
  appears to. And `TestSupport.allPixels` re-rendered the whole image per pixel, which was
  invisible on 4x4 test images and took a RAW preview from milliseconds to minutes.

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
- Stacks: group a burst or bracket so the set collapses to a single pick, with auto-stacking by
  capture time, stored beside the photos — v1.2.0

  From Aperture, and the design record is under Plan above. The part worth remembering: EXIF
  `DateTimeOriginal` is whole seconds, so a burst needs `SubsecTimeOriginal` to be grouped at all,
  and gaps are measured against the previous frame rather than the first of the group so that
  holding the shutter down stays one stack.

- Loupe (⌥⌘L): a cursor-following magnifier at one image pixel per point, sized in
  Settings — v1.1.0

  From Aperture. Follows the cursor rather than being placed, and shows 1:1 rather than a fixed
  factor, because judging focus means seeing actual pixels.
  The geometry is inverse and easy to get backwards: the view's coordinates are image pixels and
  the scroll view's magnification means one pixel occupies that many points, so reaching 1:1 needs
  scaling by `1 / magnification` — about 8x on a 36 MP file fitted to a window — and the circle
  needs the same treatment to stay a fixed size on screen. Extracted as `LoupeGeometry` so that
  arithmetic is testable; the drawing itself needs a window and is not.
  Consequence worth knowing: past 100% it magnifies *less* than the view.

## Application

- App sandbox, hardened runtime, and no network access — v0.1.0
- Custom About window — v0.7.0
- Settings window: appearance (image-area background) and general preferences — v0.8.0
- App icon — v0.8.0
- Full project documentation in the README — v0.12.0
- Unit test harness on Swift Testing, with a shared scheme so tests run from a clone — v0.13.0
- Signed, notarised, downloadable builds attached to GitHub releases — v0.13.1
- Feature tracker (this file), and file format support documented in the README — v0.15.0
