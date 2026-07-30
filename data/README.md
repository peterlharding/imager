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
