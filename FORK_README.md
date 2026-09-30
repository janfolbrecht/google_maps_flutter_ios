# RedMap fork of `google_maps_flutter_ios`

This repository is a fork of the **iOS implementation** of the Flutter `google_maps_flutter`
plugin, used by the CFAN RedMap app (`cfan_redmap_flutter`).

| | |
|---|---|
| Upstream repository | https://github.com/flutter/packages |
| Upstream path | `packages/google_maps_flutter/google_maps_flutter_ios/` |
| Upstream tag | `google_maps_flutter_ios-v2.18.6` |
| Upstream commit | `9854cd5607da4001f2dd3cbdcd6903202d28958c` |
| Package version | `2.18.6` (kept identical to upstream so the `google_maps_flutter` umbrella resolves without further overrides) |
| License | BSD-3-Clause (upstream `LICENSE`, unchanged) |
| Why | https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/69 |

The history of this repository is the upstream history of that one directory, extracted with
`git subtree split`, so `git log` shows the original Flutter commits and a future rebase onto a
newer upstream tag is an ordinary `git subtree split` + rebase.

## Scope: iOS only

Only the iOS implementation package is forked. `google_maps_flutter` (the widget package),
`google_maps_flutter_platform_interface`, `google_maps_flutter_android` and
`google_maps_flutter_web` are consumed from pub.dev unchanged. Android, web and macOS builds of
RedMap are not affected by anything in this repository.

## Why the fork exists

On iOS, panning a map with ~1000 school markers freezes the UI for around three seconds while the
plugin re-applies a few hundred `GMSMarker` adds and removes on the main thread (on iOS the raster
and platform threads are merged when a platform view is on screen). The same Dart code is smooth
on Android at 5000 markers, and the previous native Xamarin app was smooth at 20 000 through the
same Google Maps SDK. The Dart side (viewport filtering, pin cap with hysteresis, icon cache,
idle-only debounced updates, one batched update per pan) has been exhausted; the remaining cost is
inside this plugin's marker path.

The fork proceeds in the order: **measure first, then optimise only what the numbers justify.**

## What differs from upstream

1. **`FGMPerf` instrumentation** (`FGMPerf.h/.m`, plus probes in `FGMMarkerController.m` and
   `FGMGoogleMapController.m`). Runtime-enabled by the environment variable `FGM_PERF=1`; without
   it nothing is timed or logged. Emits one machine-readable `[FGMPerf]` line per marker batch
   with the time split into icon creation (by bitmap type), `GMSMarker` allocation,
   `marker.map =` assignment, the rest of the per-marker update, and cluster-manager work.
   See `BENCHMARK.md` for the protocol and the output format.
2. `FGMMarkersController` gained a `markerCount` accessor used by the instrumentation.

3. **`FGM_OPT_AX_BATCH`** (`FGMGoogleMapController.m`, `updateMarkersByAdding:changing:removing:`).
   Upstream sets `accessibilityElementsHidden = NO` on every map, and with the elements enabled
   the SDK rebuilds the accessibility items of every marker on the map after each single marker
   attached or detached. The fork hides the elements for the length of a batch that does
   something, enables them again and attaches and detaches one marker that is never drawn, which
   makes the SDK rebuild the items once. A map whose elements somebody hid is left alone.
4. **`FGM_OPT_ICON_CACHE`** (`FGMImageUtils.m`). `FGMIconFromBitmap` keeps the image it made and
   gives the same `UIImage` to every marker with an equal bitmap descriptor. The upstream
   function is unchanged under the name `FGMUncachedIconFromBitmap`.
5. `FGMOptimizations.h/.m`: the switches. Each optimisation is on by default; the environment
   variable of its name set to `0` switches it off, and with all of them off the plugin does what
   upstream does. `BENCHMARK.md` has the numbers.
6. Native tests of both in `example/ios/RunnerTests` (`GoogleMapsTests.swift`,
   `ExtractIconFromDataTests.swift`), added to the upstream files so that the Xcode project is
   untouched.
7. **`GoogleMapsFlutterIOS.accessibilityElementsHidden`** (Dart, static, default `false`) and the
   Pigeon field `PlatformMapConfiguration.accessibilityElementsHidden`. An app that sets the
   property before a map is created gets that map with its accessibility elements hidden:
   `_buildView` puts the value into the creation configuration, `interpretMapConfiguration:`
   applies it right after upstream's `accessibilityElementsHidden = NO`. Configuration updates
   send `null`, which leaves the map as it is. With the elements hidden for good the SDK no longer
   rebuilds the accessibility items after a marker change, a camera move or a cluster marker, and
   `FGM_OPT_AX_BATCH` stands aside. The price is that VoiceOver does not see the map or its
   markers. RedMap sets it to `true` in `main.dart`.

8. **`FGM_OPT_CHUNKED_BATCH`** (`FGMMarkerController.m`, `updateMarkersInSlicesByAdding:`;
   `FGMMarkerBatchQueue`). A batch of more than 50 marker operations is applied in slices: the
   first within the Pigeon call, the following ones one per frame of the display
   (`CADisplayLink`), each for `FGM_OPT_CHUNK_BUDGET_MS` (8 ms), so the map answers touches and
   draws while the markers arrive. One slice per frame, not per turn of the main queue, because
   the SDK draws on the main thread whatever changed since its last frame, and that costs more
   than changing it did (`FGM_OPT_CHUNK_PACING=queue` is the other pacing, kept for measuring).
   The queue hands out changes first, then removals and additions in turns, so the number of
   markers on the map never rises above the larger of before and after. A batch that comes
   while an earlier one is still being applied is merged with what is left: an operation a later
   batch undoes is dropped, a marker that goes and comes back stays and is changed. Clustering is
   invoked, and `FGM_OPT_AX_BATCH` brings the accessibility items up to date, once, after the last
   slice. Upstream's three passes are what `FGM_OPT_CHUNKED_BATCH=0` runs.
9. **`FGM_OPT_NEAREST_FIRST`**. The removals and the additions of a split batch are ordered by
   their distance from the camera target, so what the user looks at is finished first. What is
   left of an earlier batch is ordered again when the next one is merged.
10. **`FGM_OPT_RECYCLE_MARKERS`**. Within a batch applied in slices, a removal and the addition
    whose turn is next are one operation: the `GMSMarker` of the marker that goes stays on the
    map and takes the identifier and the properties of the marker that comes. No detach, no
    allocation, no attach. The reason is in the SDK: every attach and detach ends in its usage
    log (`-[GMSMapsSDKLogger addEvent:]`), which writes the last known map instance to the user
    defaults and so posts a defaults-changed notification, every time; that log was two thirds of
    a batch. Not for a marker of a cluster manager and not for one that is not visible.
11. **`FGM_OPT_SKIP_UNCHANGED`** (`updateMarker:fromPlatformMarker:…`). A property that already
    holds the value is not set again (the SDK logs a usage event in the setters of `draggable`,
    `rotation` and `opacity` whatever the value), and a marker that is on the map is not
    attached to it again.
12. **`FGM_OPT_ICON_DESCRIPTION`** (`FGMImageUtils.m`). An icon from the cache is an
    `FGMDescribedImage`, a `UIImage` subclass over the same bitmap that keeps the string
    `-description` returned the first time. The SDK asks a marker's image for its description
    whenever it draws a marker that is new or has changed, and `UIImage` formats it on every call.
13. `FGMPerf` also logs, per batch, the slices (`slices`, `work_ms`, `max_slice_ms`), the batches
    merged into it, the recycled markers and the frames the display link saw, and a display link
    of its own logs every gap of two frames or more between its callbacks as a `[FGMPerf] hitch`
    line: that gap, not `total_ms`, is how long the main thread did not answer.

### What an app sees of a batch applied in slices

- `updateMarkers` returns after the first slice. The markers of a large batch are on the map a
  few frames later, not when the call returns.
- An info window call (`showMarkerInfoWindow`, `hideMarkerInfoWindow`,
  `isMarkerInfoWindowShown`) for a marker whose addition or change is still waiting carries that
  one operation out first, so it behaves as if the batch had been applied whole.
- A marker whose removal is waiting is still on the map for a few frames. A tap on it, on its
  info window, or a drag of it is not sent to Dart, which no longer knows the marker; an info
  window call for it answers "Invalid markerId", as it would after the removal.
- A recycled marker is the same `GMSMarker` object with another identifier. Its info window is
  closed if it was open, its title and snippet are those of the new marker.
- The markers passed with the creation of the map (`initialMarkers`) are added in one piece, as
  upstream adds them.

### What holds memory, and how much

| What | Holds | Limit | Released |
|---|---|---|---|
| Icon cache, one per asset provider (one per map) | `UIImage` by descriptor key | 256 images (`NSCache.countLimit`) | by `NSCache` on a memory warning; with the asset provider when the map goes |
| Waiting marker operations, one queue per markers controller | the `FGMPlatformMarker`s and identifiers of batches not applied yet | what the Dart side sent and a few frames have not worked off; a later batch drops what it undoes | slice by slice; with the markers controller when the map goes (the display link holds a ticker that holds the controller weakly) |

The cache is an associated object of the asset provider and holds images only, so it adds no
reference to the map view, a marker or a controller; `FGMMarkerController.mapView` and
`FGMMarkersController.mapView` stay `weak` as upstream has them. There is no pool of markers:
a recycled marker goes straight from the marker that leaves to the marker that comes, within
one operation, and a marker that leaves with nothing to come is released as before.

### The key of the icon cache

Everything that decides the image is in the key; the screen scale is in every key.

| Descriptor | Key |
|---|---|
| default marker | `default:<hue>` |
| asset (deprecated) | `asset:<name>:<package>:<screen scale>` |
| asset image (deprecated) | `assetImage:<name>:<scale>:<screen scale>` |
| bytes (deprecated) | `bytes:<SHA-256 and length>:<screen scale>` |
| asset map | `assetMap:<asset name>:<scaling>:<pixel ratio>:<width or (null)>:<height or (null)>:<screen scale>` |
| bytes map | `bytesMap:<SHA-256 and length>:<scaling>:<pixel ratio>:<width or (null)>:<height or (null)>:<screen scale>` |
| pin configuration (advanced markers) | not cached; its glyph bitmap is |

### Known limits

- With clustering on, the cluster renderer attaches its markers outside the batch, with the
  accessibility elements enabled. `FGM_OPT_AX_BATCH` does not reach that; only
  `accessibilityElementsHidden` (item 7) does.
- The SDK also rebuilds the accessibility items on every move of the camera. Only
  `accessibilityElementsHidden` (item 7) avoids that.
- If adding a marker throws inside a batch (`InvalidByteDescriptor` from an undecodable bytes
  descriptor), the elements stay hidden. There is deliberately no `@finally`: the Pigeon handler
  does not catch the exception either, so it ends the process before anybody could see the map.
- `FGM_OPT_AX_BATCH` was checked by counting the SDK's accessibility items after each batch, not
  with VoiceOver running. Before relying on it for VoiceOver users, try it once on a device with
  VoiceOver on: the markers of a new batch must be reachable by swiping.
- The switches are environment variables, so on a device they can be set only by whoever starts
  the process (Xcode, `devicectl`). They are a tool for measuring and for finding a fault, not a
  setting of the app.
- The slices run from a display link, which the system pauses while the app is in the
  background: a batch that was being applied then waits and goes on when the app is back.
- A marker that is added without one leaving (the first load of a country) cannot be recycled
  and pays the SDK's usage log in full, 0.2 to 0.25 ms per marker on an iPad (6th generation).
  The log is inside the SDK (`GMSMapsClearcutClient setLastKnownMapInstanceID:`); the fork does
  not touch the SDK's private classes.
- What the SDK draws per changed marker (a new sprite, 0.08 ms on that iPad) is the larger half
  of a pan now and is not reachable from the plugin.
- If adding a marker throws inside a slice that the display link runs, the exception ends the
  process from the display link's callback instead of from the Pigeon handler; it ended the
  process before as well.

## How RedMap consumes it

`app/pubspec.yaml` in `cfan_redmap_flutter`:

```yaml
dependency_overrides:
  google_maps_flutter_ios:
    git:
      url: https://github.com/janfolbrecht/google_maps_flutter_ios.git
      ref: <commit SHA — always a SHA, never a branch>
```

Verify with `flutter pub deps | grep google_maps_flutter_ios`: the source must be `git`, not
`hosted`. The package is also a direct dependency (`^2.18.6`) because `main.dart` imports it to
set `GoogleMapsFlutterIOS.accessibilityElementsHidden`; the override decides the source.

## Upstream

Nothing has been offered upstream yet. What stands in the way is written down in
https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/246, which also holds the
text a pull request would start from:

- `google_maps_flutter_ios` is frozen upstream. The maintained implementations
  (`google_maps_flutter_ios_sdk9`, `_sdk10`, from `google_maps_flutter_ios_shared_code`) are
  Swift now; a pull request is a port of these changes to `ImageUtils.swift` and
  `GoogleMapController.swift`, measured again there, not a copy of this fork's commits.
- The slow marker path is https://github.com/flutter/flutter/issues/60750 (open).
- A pull request to `flutter/packages` needs the author's signed CLA and the author's own word
  on the checklist of the pull request template, the AI contribution guidelines among it.

## Maintenance

- Regenerating the Pigeon files: `dart run pigeon --input pigeons/messages.dart`, then
  `dart format -l 100 lib/src/messages.g.dart` and
  `clang-format -i --style="{BasedOnStyle: Google, ColumnLimit: 100}"` on the generated `.g.h` and
  `.g.m` (clang-format 19 or older; 23 wraps a few `NSCAssert`s differently). Upstream formats with
  its repository-wide settings, which this extracted directory does not carry, so raw Pigeon
  output differs from the committed files in every line it would have reformatted.

- Upstream states (README, 2.18.5) that `google_maps_flutter_ios` **receives no new feature
  updates**; the maintained implementations are the SDK-specific `google_maps_flutter_ios_sdk9`
  (iOS 15+) and `google_maps_flutter_ios_sdk10` (iOS 16+), which share their marker code through
  `google_maps_flutter_ios_shared_code`. A frozen upstream makes rebases rare and cheap, but it
  also means fixes have to be carried here or ported to the shared-code package.
- Rebase onto a newer upstream tag only when forced (a Flutter or Maps SDK incompatibility), not
  on every release. Estimated cost: half a day per rebase.
- Anything of general value is to be offered upstream as a PR against
  `google_maps_flutter_ios_shared_code`; the fork disappears when such a PR lands and RedMap can
  move to the maintained implementation.
