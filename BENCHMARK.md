# Marker-path benchmark

How the marker update path of this fork is measured, and the numbers. The protocol is binding:
numbers taken any other way are not comparable with the table below.

## Enabling the instrumentation

`FGMPerf` is compiled in always and switched on **at runtime** by the process environment
variable `FGM_PERF=1`. The variable is read once, on the first marker batch; without it the
instrumentation costs one static boolean read per probe and logs nothing.

How to set it for a device run:

1. Build the RedMap app in **profile** mode: `flutter build ios --profile` (from `app/`).
2. Open `app/ios/Runner.xcworkspace` in Xcode, edit the *Runner* scheme → *Run* → *Arguments* →
   *Environment Variables*, add `FGM_PERF` = `1`. Set the *Run* build configuration to *Profile*.
3. Run on the physical device from Xcode. The `[FGMPerf]` lines appear in the Xcode console (also
   in Console.app filtered by `FGMPerf`).

For Instruments, the same environment variable is set in the target's *Options* pane.

Do not use the simulator: it does not reproduce the merged raster/platform thread, and its
`GMSMarker` timings bear no relation to the device. Do not use a debug build: Dart-side overhead
dominates and the marker batches arrive at a different cadence.

## Output format

One line per `updateMarkersByAdding:changing:removing:` call, `key=value` pairs separated by
spaces, fixed key order, all durations in milliseconds:

```
[FGMPerf] batch=12 total_ms=812.40 gap_ms=35.10 add=430 change=12 remove=410 markers=1000 pass_add_ms=... pass_change_ms=... pass_remove_ms=... pass_cluster_ms=... icon_default_ms=... icon_default_n=... icon_asset_ms=... icon_asset_n=... icon_bytes_ms=... icon_bytes_n=... icon_other_ms=... icon_other_n=... alloc_ms=... alloc_n=... map_set_ms=... map_set_n=... map_nil_ms=... map_nil_n=... update_rest_ms=... update_rest_n=... cluster_ms=... cluster_n=... unaccounted_ms=...
```

| Key | Meaning |
|---|---|
| `batch` | Sequence number since app start. |
| `total_ms` | Wall time of the whole batch on the platform thread. |
| `gap_ms` | Time since the previous batch ended; `-1` for the first. Several short gaps in a row mean one pan arrived as several updates. |
| `add` / `change` / `remove` | Sizes of the three lists the Dart side sent. |
| `markers` | Markers held by the controller after the batch. |
| `pass_*_ms` | Wall time of the add pass, the change pass, the remove pass and the final `cluster` invocation. |
| `icon_default_*` | `FGMIconFromBitmap` for `BitmapDescriptor.defaultMarkerWithHue` (`[GMSMarker markerImageWithColor:]`). |
| `icon_asset_*` | `FGMIconFromBitmap` for `AssetMapBitmap` (`imageNamed:` + scaling). |
| `icon_bytes_*` | `FGMIconFromBitmap` for `BytesMapBitmap` (PNG decode + scaling). |
| `icon_other_*` | Any other bitmap type (deprecated descriptors, pin config). |
| `alloc_*` | `[GMSMarker markerWithPosition:]`. |
| `map_set_*` | `marker.map = mapView` (or `= nil` for an invisible marker) at the end of `updateMarker:`. |
| `map_nil_*` | `marker.map = nil` in `removeMarker`. |
| `update_rest_*` | `updateMarker:` wall time minus its icon and map-set phases (anchor, position, zIndex, rotation, info window, opacity). |
| `cluster_*` | Cluster manager `addItem:` / `removeItem:` per marker plus the final `cluster` call. |
| `unaccounted_ms` | `total_ms` minus every measured phase: dictionary work, Pigeon accessors, anything not wrapped. |

`*_ms` is the sum over the batch, `*_n` the number of calls. Divide for a per-call average.

Not covered by the probes: Pigeon decoding of the message (happens before the handler is called)
and the Dart side of the update. Those are measured, if needed, from Dart.

## Protocol

1. Device: **iPad (3rd generation) or the oldest iPad available, iOS 17.7 or newer**, connected by
   cable, **profile** build, `FGM_PERF=1`. Write the exact device model and iOS version into the
   results header; numbers from different devices are never mixed in one column.
2. Sign in with the integration-test account. Select a country with more than 1000 schools
   (India). Settings: **clustering off**, pin cap **1000**.
3. Runs, in this order, from the same starting camera position each time:
   - **A** — first load of the country (one batch).
   - **B** — five big pans in a dense area: drag far enough that the whole viewport changes, lift
     the finger, wait until every pin is drawn.
   - **C** — five small pans back and forth (a quarter of the screen and back).
   - **D** — switch clustering **on**, one big pan.
4. Collect every `[FGMPerf]` line from the console. For each run compute median and maximum of
   `total_ms`, and for the median batch of run B the phase breakdown in milliseconds and percent.
5. Repeat the runs until the medians of two consecutive repetitions agree within about 20 %; record
   the spread. One run is not a measurement.
6. Optional: Instruments → Time Profiler over one big pan, export the `.trace` next to the results.

## Results

### Baseline (fork with instrumentation only, no optimisation)

| Run | Batches | total_ms median | total_ms max | add / change / remove (median) | markers after |
|---|---|---|---|---|---|
| A first load | | | | | |
| B big pan | | | | | |
| C small pan | | | | | |
| D big pan, clustering on | | | | | |

Breakdown of the median run-B batch:

| Phase | Calls | ms | % of batch |
|---|---|---|---|
| icon_default | | | |
| icon_asset | | | |
| icon_bytes | | | |
| icon_other | | | |
| alloc | | | |
| map_set | | | |
| map_nil | | | |
| update_rest | | | |
| cluster | | | |
| unaccounted | — | | |
| **total** | — | | 100 % |

Environment: _device, iOS, Flutter, fork SHA, GoogleMaps pod, date — to be filled in._

### After optimisation

One column per optimisation, each measured with its `FGM_OPT_*` switch on and off, same protocol.
Added when the optimisations land.
