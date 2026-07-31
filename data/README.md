# Test images

Images for exercising Imager by hand.
Nothing here is used by the app or the test suite; it is material for driving the real
application, which is where the bugs that unit tests cannot reach have shown up.

Regenerate everything with:

```sh
swift data/make-test-images.swift data
```

The generator draws straight into a `CGContext` of the exact pixel size.
Drawing via `NSImage.lockFocus` instead would use the display's backing scale and silently
produce images at twice the intended size on a Retina Mac.

## `adjustment-test.png`

2400 × 1200, six horizontal bands for the Adjust inspector pane.

| Band | Contents | Use it for |
| --- | --- | --- |
| 1 (top) | Full ramp, black to white | Banding. Smooth to start with, so stepping that appears after an adjustment was introduced by the pipeline |
| 2 | Narrow midtones, 118 to 138 | The worst case: about 20 tonal levels stretched across 2400 pixels |
| 3 | Highlights, 200 to 255 | Pulling Highlights down |
| 4 | Shadows, 0 to 55 | Opening Shadows up |
| 5 | Saturated hue sweep | Hue and Saturation |
| 6 (bottom) | Muted hue sweep, 25% saturation | Vibrance, which should move this band far more than band 5 |

Band 2 is **already visibly stepped in the original file**.
That is what twenty tonal levels across 2400 pixels looks like in 8 bits, not a defect.
Band 1 is the honest banding test, because it starts smooth.

## Camera RAW

Not in the repository: a NEF or CR2 is tens of megabytes, and RAW extensions are gitignored.

RAW development cannot be tested without a real file, because behaviour varies by camera and
decoder — `CIRAWFilter` exposes nine `Supported` flags precisely because not every control applies
to every file. Drop a RAW here locally when working on it.

## `slideshow/`

Five 1200 × 800 images numbered 1 to 5 in distinct colours, for folder browsing and the
slideshow: the numerals make it obvious which image is showing and which way an ordering runs.

Useful for sort order (name, date modified, file size, reversed), ← / → navigation, the
thumbnail sidebar, and watching a slideshow advance and wrap.

## `stacks/`

Ten 1200 × 800 JPEGs laid out like a shoot, for stacking.

JPEG rather than PNG because stacking groups by EXIF capture time, and PNG carries none — the
rest of this folder is invisible to the feature for exactly that reason.

| Frames | Label | Spacing |
| --- | --- | --- |
| `shot-01` to `shot-04` | burst 1–4 | a quarter of a second apart |
| `shot-05` | single | four minutes after the burst |
| `shot-06` to `shot-08` | bracket −1, 0, +1 | two seconds apart |
| `shot-09`, `shot-10` | try 1, try 2 | twenty seconds apart |

The spacing gives each preset in **View ▸ Stacks ▸ Stack Photos…** a different answer: half a
second finds the burst alone, two seconds adds the bracket, and a minute also picks up the two
tries. Every gap *between* groups is well over a minute, so the lone frame stays lone throughout.

The burst is the interesting case. All four frames carry the same `DateTimeOriginal`, since EXIF
records whole seconds; they are told apart only by `SubsecTimeOriginal`, which is what a camera
writes for a burst and what Imager reads.

Stacking writes `.imager/stacks.json` into the folder. Delete that directory to start over.
