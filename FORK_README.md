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
5. `FGMOptimizations.h/.m`: the two switches. Each optimisation is on by default; the environment
   variable of its name set to `0` switches it off, and with both off the plugin does what
   upstream does. `BENCHMARK.md` has the numbers of every combination.
6. Native tests of both in `example/ios/RunnerTests` (`GoogleMapsTests.swift`,
   `ExtractIconFromDataTests.swift`), added to the upstream files so that the Xcode project is
   untouched.

### What holds memory, and how much

| What | Holds | Limit | Released |
|---|---|---|---|
| Icon cache, one per asset provider (one per map) | `UIImage` by descriptor key | 256 images (`NSCache.countLimit`) | by `NSCache` on a memory warning; with the asset provider when the map goes |

The cache is an associated object of the asset provider and holds images only, so it adds no
reference to the map view, a marker or a controller; `FGMMarkerController.mapView` and
`FGMMarkersController.mapView` stay `weak` as upstream has them. There is no pool of markers.

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
  accessibility elements enabled. `FGM_OPT_AX_BATCH` does not reach that.
- The SDK also rebuilds the accessibility items on every move of the camera. The fork does not
  change that.
- The switches are environment variables, so on a device they can be set only by whoever starts
  the process (Xcode, `devicectl`). They are a tool for measuring and for finding a fault, not a
  setting of the app.

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
`hosted`.

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
