# Architecture

How a camera frame becomes four servo angles and a drawn skeleton.

## The pipeline

```
camera plugin (NV21, 1 plane)
        │
        │  rotation compensation computed in Dart
        │  from sensorOrientation + deviceOrientation
        ▼
MethodChannel "smartarm/hands", method "detect"
        │  { bytes, width, height, rotation }
        ▼
Kotlin worker thread (single-threaded executor)
        │  NV21 → ARGB_8888, rotated upright in one pass
        │  into a reused IntArray and a reused Bitmap
        ▼
MediaPipe HandLandmarker, RunningMode.VIDEO, numHands = 1
        │
        ▼
21 × 3 doubles back over the channel
        │
        ▼
Dart: servo mapping  →  CustomPainter overlay + readout bars
```

### 1. Capture

`CameraController` runs at `ResolutionPreset.medium` (720×480 on the test device) with
`ImageFormatGroup.nv21`, which delivers a single packed plane. `startImageStream` fires
`_onFrame` for every frame.

Up to **two frames are kept in flight** (`_inFlight`), and any frame arriving beyond that is
dropped. The native worker is single-threaded, so the queued frame begins converting the
instant the previous one leaves MediaPipe rather than after a full channel round trip. This
one change took the app from 12 fps to 25 fps — with a strict one-at-a-time gate, the
round-trip latency is dead time on every single frame. The depth-2 bound keeps latency from
growing without limit.

### 2. Rotation compensation

The camera buffer arrives in the sensor's own orientation, which is almost never upright.
Dart computes the clockwise rotation needed to correct it from the camera's
`sensorOrientation` and the controller's current `deviceOrientation`:

```dart
final rotation = description.lensDirection == CameraLensDirection.front
    ? (description.sensorOrientation + deviceRotation) % 360
    : (description.sensorOrientation - deviceRotation + 360) % 360;
```

where `deviceRotation` is 0/90/180/270 for portraitUp/landscapeLeft/portraitDown/
landscapeRight. The sign differs by lens because the front sensor is mirrored relative to
the rear one.

This number is passed to Kotlin rather than applied in Dart — rotating there would mean a
second full pass over the pixels.

### 3. Crossing to native

The `smartarm/hands` `MethodChannel` has two methods:

- `start` — builds the `HandLandmarker`. Called once, before the camera opens.
- `detect` — one frame in, landmarks out.

Both are dispatched onto a single-threaded executor so MediaPipe is never re-entered
concurrently and `RunningMode.VIDEO`'s timestamp ordering is preserved. Results are posted
back to the main looper before `result.success(...)`, since Flutter requires replies on the
platform thread.

**Why only landmarks come back.** The frame goes native as ~518 KB of NV21 and comes back
as 63 doubles — about 500 bytes. Returning pixels instead would mean shipping a megabyte of
RGBA back across the channel every frame and decoding it in Dart, for no gain: the preview
is already on screen as a platform texture. The overlay is drawn as vector strokes over
that texture, so the pixels only ever travel one way.

### 4. Colour conversion and rotation, fused

`nv21ToArgb` walks the source frame once, converting YUV to RGB with the standard
fixed-point integer coefficients and writing each pixel straight to its **rotated**
destination index.

It also **decimates by two** on the way through, so a 720×480 capture becomes a 240×360
upright image for detection. The landmarker rescales its input to 192×192 internally, so
that detail was being thrown away regardless, and skipping every other pixel cuts the
conversion to a quarter of the work — measured at 17 ms before, 2 ms after. The preview the
user sees is a separate camera texture and stays at full resolution. Landmarks come back
normalised to 0..1, so nothing downstream needs to know the detection input was smaller.

With `sw = w / 2`, `sh = h / 2`, and `si`/`sj` the decimated source coordinates:

| rotation | destination index | output size |
| --- | --- | --- |
| 0 | `sj * sw + si` | `sw × sh` |
| 90 | `si * sh + (sh - 1 - sj)` | `sh × sw` |
| 180 | `(sh - 1 - sj) * sw + (sw - 1 - si)` | `sw × sh` |
| 270 | `(sw - 1 - si) * sh + sj` | `sh × sw` |

Doing the rotation inside the conversion loop avoids a second pass over the whole image. The
`IntArray` and the `Bitmap` are both cached and reused across frames; only a change in
frame size reallocates them. Chroma is sampled per 2×2 block in NV21, so dropping every
other pixel costs no colour accuracy at all.

Note NV21 stores the chroma plane as interleaved **V then U**, which is why `v` is read at
`uvIndex` and `u` at `uvIndex + 1`.

### 5. Inference

`HandLandmarker` is built with `RunningMode.VIDEO`, `numHands = 1`, and detection,
presence and tracking confidences all at 0.5 — the same settings as the Python's
`mp_hands.Hands(model_complexity=0, min_detection_confidence=0.5, min_tracking_confidence=0.5)`.

The delegate is tried as GPU first and falls back to CPU if the driver refuses, since GPU
roughly halves inference time but is not available everywhere.

`RunningMode.VIDEO` requires strictly increasing timestamps, so the code guards against a
clock that returns the same millisecond twice:

```kotlin
val ts = System.currentTimeMillis().let { if (it <= lastTimestamp) lastTimestamp + 1 else it }
```

Landmarks come back normalised to 0..1 in the **upright, unmirrored** frame — the space the
rotated bitmap defines.

## The ported maths

All of this lives in `lib/main.dart` and mirrors the Python one to one. Landmark indices
are MediaPipe's standard hand model: 0 is the wrist, 5 the index MCP knuckle, and 4/8/12/
16/20 the fingertips.

### Derived quantities

| Quantity | Definition |
| --- | --- |
| `palm_size` | 3D distance from the wrist (0) to the index MCP (5) |
| `is_fist` | `sum(3D distance from wrist to landmarks 7, 8, 11, 12, 15, 16, 19, 20) / palm_size < 7` |

`fist_threshold = 7`. Dividing by `palm_size` is what makes the test scale-invariant — a
hand near the camera and a hand far away give the same ratio.

### Servo mappings

Every channel is `map_range(value, in_min, in_max, out_min, out_max)`:

| Servo | Input | Clamped to | Maps to | Notes |
| --- | --- | --- | --- | --- |
| **X** (base) | `int((wrist.x − indexMCP.x) / palm_size × 180 / π)` | −50 … 20 | 150 … 0 | palm tilt, output inverted |
| **Y** (lift) | `wrist.y` | 0.3 … 0.9 | 180 … 0 | output inverted |
| **Z** (reach) | `palm_size` | 0.1 … 0.3 | 180 … 10 | output inverted |
| **Claw** | `is_fist` | — | 0 closed / 60 open | not a range |

Centre/rest values are `x_mid = 75`, `y_mid = 90`, `z_mid = 90`, claw open.

### Two details that had to be preserved exactly

**`map_range` must floor toward negative infinity.** The Python is:

```python
map_range = lambda x, in_min, in_max, out_min, out_max: \
    abs((x - in_min) * (out_max - out_min) // (in_max - in_min) + out_min)
```

`//` is floor division, not truncation, and the two differ for negative numerators. All
three mappings invert their output, so `(out_max - out_min)` is negative in every case and
the numerator runs negative throughout. Using truncation would shift results by one across
the whole range. The Dart version therefore floors explicitly:

```dart
final scaled = (x - inMin) * (outMax - outMin) / (inMax - inMin);
return (scaled.floorToDouble() + outMin).abs();
```

Note the `abs()` is applied after adding `out_min`, not before — same as the Python.

The X input keeps Python's `int()` semantics separately: that one *truncates* toward zero,
so Dart uses `truncateToDouble()` there. (The Python writes `3.1415926` where Dart uses
`math.pi`; the difference is about 5 × 10⁻⁸ relative and never changes an integer result.)

**Detection runs on the unflipped frame.** The Python calls `hands.process(image)` first
and only then `cv2.flip(image, 1)` for display. That ordering matters: the X mapping is
driven by `wrist.x − indexMCP.x`, whose sign flips under a horizontal mirror, which would
send the base servo the wrong way. This port keeps the same ordering — the landmarks used
for the maths are always from the unmirrored frame, and the Mirror toggle only affects
where the painter puts them on screen.

### Holding the last reading

In the Python, `servo_angle` is a module-level variable reassigned only inside
`if results.multi_hand_landmarks:`. When the hand leaves frame it simply keeps its previous
value. The Dart does the same:

```dart
if (hand != null) _servo = landmarkToServoAngle(hand);
```

The status line reads "no hand" while this is happening, so it is clear the numbers are
stale rather than live.

## Drawing

The overlay is a `CustomPainter` passed as `CameraPreview`'s `child`, which places it
inside the preview's own aspect-ratio box. That box is exactly the frame the landmarks came
from, so normalised coordinates map onto the canvas by a plain multiply — no letterboxing
maths, no drift when the window resizes.

The painter draws the 21 standard hand connections as green bones with red joints, then
the `[x, y, z, claw]` list in red at the top left.

## Performance notes

All figures measured on the test device, a Realme RMX2001 (Helio G90T, Mali-G76 MC4). The
app prints its own frame rate in the status line under the buttons, and the native side logs
a rolling 30-frame average under the `SmartArm` tag:

```
frames=630 hands=0 240x360 on GPU convert=2ms detect=37ms
```

How it got from 4.5 fps to 25 fps, in the order the changes were made:

| change | convert | detect | frame rate |
| --- | --- | --- | --- |
| starting point — CPU delegate, full resolution, rebuild every frame | 17 ms | 63 ms | 4.5 fps |
| notifier-driven repaints instead of `setState` per frame | 17 ms | 47 ms | 10 fps |
| GPU delegate | 17 ms | 47 ms | 10 fps |
| half-resolution detection input | 2 ms | 39 ms | 12 fps |
| two frames in flight | 2 ms | 37 ms | **25 fps** |

Three things mattered, roughly equally:

1. **Not rebuilding the widget tree at frame rate.** The first version called `setState` on
   every result, which rebuilt `CameraPreview` and the whole control panel. Per-frame results
   now ride `ValueNotifier`s: the painter takes them as its `repaint` listenable so a new
   result repaints the overlay without rebuilding anything above it, and the readout bars sit
   behind a `ValueListenableBuilder` of their own.
2. **Cheaper input.** GPU delegate plus half-resolution detection.
3. **Hiding the channel round trip** by allowing a second frame to queue behind the worker.

At 37 ms of inference the pipeline is now bounded by MediaPipe itself — a ceiling of about
26 fps on this hardware. Going meaningfully past that would mean dropping the MethodChannel
entirely and driving CameraX natively into a Flutter texture, which is a much larger change
than any of the above.
