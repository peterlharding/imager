# Working on Imager

A native macOS image viewer and light editor. SwiftUI and AppKit, sandboxed, no dependencies.

## Read these before planning anything

- **`FEATURES.md`** is the backlog *and* the record of design decisions.
  It carries the reasoning, not just the intentions, including several "this was measured, do not
  do X" notes that exist to stop the obvious-but-useless optimisation being attempted again.
- **`RELEASING.md`** is the release process. Follow it exactly; it has been corrected by things
  going wrong.
- **`CHANGELOG.md` is hand-edited here.** PLH's global rule against editing changelogs by hand does
  not apply: this repository has no generator, and `RELEASING.md` step 3 requires it.

## Invariants worth knowing before changing anything

- **Imager never writes to the file the user opened.** Editing happens in memory; saving writes a
  copy. Batch processing goes further and refuses the source folder as a destination.
- **Edits are a replayable `[ImageEdit]` log**, not mutations of a bitmap. Replay is every geometry
  edit in order, then only the *last* adjustment, since adjustment values are absolute.
  New adjustments belong as `ImageEdit` cases so they join undo and recipes for free.
- **RAW settings are deliberately not an `ImageEdit`.** An edit transforms an image; RAW development
  produces one from the URL before any image exists. They ride in the undo snapshots alongside the
  edit list.
- **Undo and redo hold snapshots of the whole edit list**, not individual edits, because actions
  like applying a recipe rewrite the history rather than appending to it.
- **Hold one `RawDeveloper` per open file.** A fresh `CIRAWFilter` per render costs 370-560 ms on a
  36 MP file and never better than 86 ms at any scale; a held instance costs about 7 ms.

## How to work here

**Measure rather than reason.** Nearly every plan in this project was corrected by a measurement
that took minutes: the highlight/shadow filter, the adjustment pipeline's speed, whether 16-bit
rendering would reduce banding, how RAW development should be made fast. Check the assumption
before building on it.

**Probing an API with a standalone `swift` script proves less than it looks.** A script compiles
against the host OS, not this project's deployment target, so availability problems slip through.
Build it in the app when availability matters.

**Verify new tests can fail.** Mutate the code under test, watch the suite go red, then restore it.
Back the file up first if it is not yet committed, since `git checkout` cannot restore an untracked
file.

**The test suite cannot see sandbox or menu-bar behaviour.** Security-scoped access only exists in a
real sandboxed process, and SwiftUI menu enablement has to be looked at. Several real bugs have
shipped past a fully green suite. Anything touching either needs a run of the actual app, and PLH
is the one who can confirm it.

**When a value contradicts something already established, ask before acting on it.** PLH's keyboard
sometimes drops characters. The tell is conflict with a known fact: a number outside a range just
stated, a version that does not exist, a name matching nothing present. Name that specific
inconsistency rather than substituting an interpretation of your own, and do not reshape the work so
the suspect value fits. This is not licence to second-guess ordinary answers.

## Test data

`data/` holds images for driving the app by hand, and the script that regenerates them.
Camera RAW files are gitignored, so RAW tests are gated with `.enabled(if: hasRawFile)` and skip
rather than fail on a clone without one.
Generate test images by drawing into a `CGContext` of the exact size: `NSImage.lockFocus` draws at
the display's backing scale and silently doubles the size on a Retina Mac.
