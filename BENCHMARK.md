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

## Switching an optimisation off

Each optimisation of the fork is on by default and is switched off by an environment variable
of the process, read once: `FGM_OPT_AX_BATCH=0`, `FGM_OPT_ICON_CACHE=0`. With both off the plugin
does what upstream does. They are set the way `FGM_PERF` is; from the command line
`xcrun devicectl device process launch --environment-variables '{"FGM_PERF":"1","FGM_OPT_AX_BATCH":"0"}' ...`.

The later optimisations have their switches too: `FGM_OPT_CHUNKED_BATCH`, `FGM_OPT_NEAREST_FIRST`,
`FGM_OPT_RECYCLE_MARKERS`, `FGM_OPT_SKIP_UNCHANGED`, `FGM_OPT_ICON_DESCRIPTION` (each off with
`0`), and two knobs of the slices: `FGM_OPT_CHUNK_BUDGET_MS=<milliseconds per slice>` (8) and
`FGM_OPT_CHUNK_PACING=queue` (a slice per turn of the main queue instead of one per frame).
Recycling happens only inside a batch applied in slices; to see it without slices give the
slices a budget no batch reaches (`FGM_OPT_CHUNK_BUDGET_MS=100000`).

## Output format

One line per `updateMarkersByAdding:changing:removing:` call, `key=value` pairs separated by
spaces, fixed key order, all durations in milliseconds:

```
[FGMPerf] batch=12 total_ms=812.40 gap_ms=35.10 add=430 change=12 remove=410 markers=1000 pass_add_ms=... pass_change_ms=... pass_remove_ms=... pass_cluster_ms=... icon_default_ms=... icon_default_n=... icon_asset_ms=... icon_asset_n=... icon_bytes_ms=... icon_bytes_n=... icon_other_ms=... icon_other_n=... alloc_ms=... alloc_n=... map_set_ms=... map_set_n=... map_nil_ms=... map_nil_n=... update_rest_ms=... update_rest_n=... cluster_ms=... cluster_n=... unaccounted_ms=... ax_refresh_ms=... ax_refresh_n=...
```

Before the first batch one line names the switches the process runs with:

```
[FGMPerf] enabled=1 clock=CACurrentMediaTime units=ms opt_ax_batch=1 opt_icon_cache=1
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
| `ax_refresh_*` | The attach and detach of one undrawn marker after the batch, which makes the SDK rebuild its accessibility items once (`FGM_OPT_AX_BATCH`). Zero calls when the switch is off or the batch is empty. |

| `slices`, `slice_ops` | Slices the batch was applied in (1 for a batch in one piece) and the marker operations they carried out; a recycled marker is two. |
| `work_ms`, `max_slice_ms` | Time the plugin held the main thread, all slices together, and the longest slice. `unaccounted_ms` is `work_ms` minus the phases. |
| `merged` | Batches that arrived while this one was being applied and were merged into it. Their sizes are added to `add` / `change` / `remove`. |
| `frames`, `max_frame_gap_ms` | Callbacks of FGMPerf's display link between the begin and the end of the batch, and the longest time between two of them. |
| `t_begin`, `t_end` | Begin and end of the batch on the clock of the `hitch` lines (`CACurrentMediaTime`, seconds). |
| `recycled`, `pass_recycle_ms` | Markers that went and came as one (`FGM_OPT_RECYCLE_MARKERS`) and the time that took. Their icon and update_rest phases are counted as for any marker. |

`*_ms` is the sum over the batch, `*_n` the number of calls. Divide for a per-call average.

**`total_ms` of a batch applied in slices is the time to its last marker**, with the run loop
turning in between, not the time the main thread was held. That is what the second kind of line
is for:

```
[FGMPerf] hitch gap_ms=61.7 t_end=76456.5887
```

With `FGM_PERF=1` a display link runs on the main run loop and logs every gap of 34 ms (two
frames at 60 Hz) or more between two of its callbacks. A gap is a stretch in which the main
thread answered nothing, whoever held it: the Dart side building the markers, the batch or a
slice of it, the SDK drawing what changed. Lay the gaps over the batches by `t_begin` and `t_end`;
the longest gap from a quarter of a second before a batch to a quarter of a second after it is
the number to compare (`hitch` below).

Not covered by the probes: Pigeon decoding of the message (happens before the handler is called)
and the Dart side of the update. Those are measured, if needed, from Dart.

## Protocol

1. Device: **iPad (3rd generation) or the oldest iPad available, iOS 17.7 or newer**, connected by
   cable, **profile** build, `FGM_PERF=1`. Write the exact device model and iOS version into the
   results header; numbers from different devices are never mixed in one column.
2. Only the main map may be on screen: the counters are per process, not per map view, so a
   second `GMSMapView` would interleave its batches. Sign in with the integration-test account. Select a country with more than 1000 schools
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

Fork commit `81458aa`, measured 2026-09-29. Pin cap 1000, clustering off except run D, fast
Wi-Fi. The country is the 5000-school `TSTBIG` of the RedMap emulator seed, not India, and the
device is an iPad (6th generation), not a 3rd generation one: keep both for the "after" column.

| Run | Batches | total_ms median | total_ms max | add / change / remove (median) | markers after |
|---|---|---|---|---|---|
| A first load | 7 | 5281 | 5559 | 1000 / 0 / 0 | 1000 |
| B big pan | 10 | 11 215 | 13 215 | 785 / 0 / 785 | 1000 |
| C small pan, cap reached in the viewport | 10 | 7186 | 8046 | 536 / 0 / 536 | 1000 |
| C small pan, viewport below the cap | 10 | 163 | 418 | 12 / 0 / 12 | 1000 |
| D big pan, clustering on | 1 | 2398 | 2398 | 684 / 0 / 684 | 1000 |

Run B in two sessions from a fresh app start: medians 11 019 and 11 411 ms. Every pan reached the
plugin as one batch. Run D times only the hand-over to the cluster manager; the renderer attaches
the markers afterwards, outside the batch.

Breakdown of the median run-B batch (`total_ms` 11 019, 790 added, 790 removed, 1000 on the map):

| Phase | Calls | ms | % of batch |
|---|---|---|---|
| icon_default | 0 | 0.0 | 0.0 % |
| icon_asset | 790 | 2642.8 | 24.0 % |
| icon_bytes | 0 | 0.0 | 0.0 % |
| icon_other | 0 | 0.0 | 0.0 % |
| alloc | 790 | 84.2 | 0.8 % |
| map_set | 790 | 4306.4 | 39.1 % |
| map_nil | 790 | 3901.3 | 35.4 % |
| update_rest | 790 | 66.7 | 0.6 % |
| cluster | 1 | 0.2 | 0.0 % |
| unaccounted | — | 17.9 | 0.2 % |
| **total** | — | 11 019.4 | 100 % |

Cost of one call against the number of markers on the map at that moment, over all batches:

| Phase | ms per call |
|---|---|
| map_set | 0.07 + 0.00396 × markers on the map (R² 0.977, 100 to 2500 markers) |
| map_nil | 0.33 + 0.00358 × markers on the map (R² 0.970, 100 to 1500 markers) |
| icon_asset | 3.29, constant |
| alloc | 0.10, constant |
| update_rest | 0.08, constant |

Time Profiler over one big pan (15 754 ms of main-thread samples in the batch):

| Where | ms | % |
|---|---|---|
| `-[GMSVectorMapView buildVisibleAccessibilityItems]` under `-[GMSOverlay setMap:]`, attach | 5964 | 37.9 % |
| the same under `-[GMSMapView cleanupRemovedOverlay:overlayID:]`, detach | 5574 | 35.4 % |
| `+[FlutterDartProject lookupKeyForAsset:]` under `FGMIconFromBitmap` | 3376 | 21.4 % |
| everything else | 840 | 5.3 % |

The SDK rebuilds the accessibility items of every marker on the map after each marker attached or
detached; `FGMGoogleMapController.m` sets `accessibilityElementsHidden = NO` on the map view. The
icon time is Flutter resolving the asset path on disk on every call, not decoding or scaling.

On the 3G profile of the Network Link Conditioner the same gestures cost the same: 6.76 ms per
marker operation against 6.78 ms on fast Wi-Fi, and the only main-thread hang in either trace is
the batch.

Environment: iPad (6th generation) A1893 `iPad7,5`, iOS 17.7.11, portrait; RedMap 4.0.14+415
profile build; Flutter 3.44.0, `google_maps_flutter` 2.18.1; GoogleMaps pod 9.4.0,
Google-Maps-iOS-Utils 6.1.0; Xcode 26.3. The full write-up and the driver that made the gestures
are in the RedMap repository under `.AI/perf/`.

### After optimisation

Fork commit `f69b725`, measured 2026-09-29 and 2026-09-30 on the device, the country, the cap and
the network of the baseline, by the same gestures. One build, the switches set per session.

Run B, five big pans per session (ten with both switches on):

| `FGM_OPT_AX_BATCH` | `FGM_OPT_ICON_CACHE` | total_ms median (min to max) | ms per marker operation |
|---|---|---|---|
| off | off | 10 837 (10 053 to 11 640) | 6.94 |
| on (`e4f5ec3`) | off | 2043 (1550 to 2899) | 1.72 |
| off | on (`f69b725`) | 7790 (6991 to 8139) | 4.95 |
| on | on | 223 (168 to 268) | 0.145 |

The batches differ in size between sessions, so the cost of one operation is the number to
compare. The row with both switches off is the baseline measured again.

All runs with both switches on:

| Run | Batches | total_ms median | total_ms max | Baseline median |
|---|---|---|---|---|
| A first load, 1000 adds | 5 | 192 | 222 | 5281 |
| B big pan | 10 | 223 | 268 | 11 215 |
| C small pan, cap reached in the viewport | 10 | 125 | 160 | 7186 |
| D big pan, clustering on | 1 | 105 | 105 | 2398 |
| A first load, cap 5000 | 2 | 877, 974 | | 65 676 (65 853 with both switches off) |

The ten big pans with both switches on, by phase:

| Phase | ms per call | % of the batches |
|---|---|---|
| icon_asset | 0.016 | 5.4 % |
| alloc | 0.055 | 18.6 % |
| map_set | 0.073 | 25.0 % |
| map_nil | 0.075 | 25.6 % |
| update_rest | 0.051 | 17.5 % |
| ax_refresh | 8.5, once per batch | 3.8 % |
| unaccounted | | 3.9 % |

Attaching and detaching a marker no longer depend on the number of markers on the map (0.046 to
0.069 ms per attach with 5000 on it).

The SDK's accessibility items were counted after every batch in a build that logged the count:
631 to 816 with `FGM_OPT_AX_BATCH` on, 631 to 824 with it off, 1000 markers on the map. Screenshots
of the RedMap test country with both switches on and with both off are the same pixels.

Not tried, because the target (a big pan under 500 ms) is met without them: pooling of
`GMSMarker`, the batch inside one `CATransaction`, skipping the icon of a changed marker when it
is the one the marker has.

Native tests (`example/ios/RunnerTests`, iPhone 16 simulator, iOS 18.3.1): 78 tests in 12 suites
passed, seven of them new (four of the icon cache, three of the accessibility batch).

### Slices, recycled markers (2026-09-30)

Same device, country, cap and gestures. What is measured is no longer only the batch: a display
link logs how long the main thread goes without a frame (`hitch`, see "Output format"), and
that number was taken for the batch in one piece as well. Run B, five big pans per session,
median (minimum to maximum). "One piece" is `FGM_OPT_CHUNKED_BATCH=0`.

| Fork commit, switches | Plugin work, ms | Time to the last marker, ms | Longest gap between frames, ms | ms per marker operation |
|---|---|---|---|---|
| `d8d9dfc`, one piece (what `3708123` did) | 208 (182–235) | 208 | 386 (261–477) | 0.132 |
| `d8d9dfc`, slices per turn of the main queue | 313 (297–325) | 668 (622–674) | 60 (46–62) | 0.203 |
| `d66deee`, recycling, in one slice | 46 (39–56) | 46 | 259 (169–289) | 0.031 |
| `d66deee`, recycling, slices per queue turn | 57 (48–68) | 222 (186–260) | 77 (72–102) | 0.037 |
| `d66deee`, recycling, slices per frame | 59 (53–63) | 284 (247–311) | 54 (51–73) | 0.037 |
| `ce23959`, all on (per frame, 8 ms, icon description) | 59 (49–69) | 225 (160–246) | 49 (43–63) | 0.039 |
| `ce23959`, all on, second session | 64 (41–86) | 212 (156–258) | 55 (42–68) | 0.041 |
| `ce23959`, `FGM_OPT_ICON_DESCRIPTION=0` | 60 (52–65) | 267 (225–303) | 53 (46–64) | 0.037 |
| `ce23959`, `FGM_OPT_RECYCLE_MARKERS=0` | 318 (252–375) | 727 (602–880) | 47 (34–63) | 0.208 |
| `ce23959`, `FGM_OPT_SKIP_UNCHANGED=0`, recycling on | 284 (276–316) | 843 (831–911) | 56 (43–73) | 0.186 |
| `ce23959`, `FGM_OPT_NEAREST_FIRST=0` | 47 (40–66) | 162 (154–264) | 50 (38–61) | 0.035 |
| `ce23959`, one piece | 179 (136–204) | 179 | 239 (222–334) | 0.117 |

- The batch in one piece held the main thread for 0.39 s, not for the 0.21 s of `total_ms`: the
  SDK draws every marker that changed in the frame after the batch, and its usage log flushes
  on the main queue.
- Slices without recycling make the gap short and the pan three times as long. Recycling
  without slices makes the plugin fast and leaves a gap of 0.26 s, the SDK drawing 700 markers
  in one frame. It takes both.
- A slice per frame beats a slice per turn of the main queue once markers are recycled: the
  queue puts two or three slices between two frames and the frame that draws them is long.
- With `FGM_OPT_SKIP_UNCHANGED` off a recycled marker has every property set again while on the
  map, and a pan takes 843 ms; from `64264ba` on recycling is off when that switch is off.
- Ordering cost the first slice its whole budget (10 ms for 1400 operations), which is the
  frame by which `FGM_OPT_NEAREST_FIRST=0` is faster; `64264ba` orders a fresh batch without a
  lookup per marker.

Other runs on `ce23959`, all on: first load of 1000 markers 583 and 550 ms to the last marker
with a longest gap of 53 and 48 ms (one piece: 150 to 218 ms and a gap of 278 to 456 ms); run C
159 ms (111 to 202) with a gap of 43 ms (35 to 54). A first load has nothing to recycle and is
applied at about 31 markers per frame.

Time Profiler, one big pan, `ce23959`, all on: no main-thread hang in the trace. Of 210 ms of
main-thread samples between the batch arriving and its last marker, 102 are the SDK drawing
(`GMSEntityRendererView draw`, seven frames), 42 the slices, 23 Flutter, 17 layer commits, 16
the Pigeon handler (decoding, merging, ordering, first slice) and 4 the SDK's usage log. The same
pan on `3708123`: one hang of 325 ms, the usage log 249 ms (173 inside the batch, in
`-[GMSMapsSDKLogger addEvent:]` under every attach and detach, 76 on the main queue after it).

Native tests (`example/ios/RunnerTests`, iPhone 16 simulator, iOS 18.3.1) on `64264ba`: 109
tests in 12 suites passed; 27 are new with this work (the queue, the slices, recycling, skip
unchanged, the icon description). Running them needs `pod install` in `example/ios` first,
because the fork added source files; that rewrites `Runner.xcodeproj`, which is not committed.
