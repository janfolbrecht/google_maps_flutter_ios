// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition (https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/69).
//
// Lightweight timing instrumentation for the marker update path. Enabled at runtime by the
// process environment variable `FGM_PERF=1`; read once, on first use. When the variable is absent
// every function in this file is a no-op that costs one static BOOL read, and nothing is logged.
//
// Timing uses CACurrentMediaTime() and accumulates into static counters; the single NSLog per
// batch happens in FGMPerfEndBatch(), never inside a per-marker loop.
//
// While enabled, a display link on the main run loop also watches how long the main thread goes
// without answering: every gap of two frames or more between two of its callbacks is logged as a
// `[FGMPerf] hitch` line, whatever caused it (a marker batch, the Dart side, the SDK drawing).

@import Foundation;
@import QuartzCore;

#import "google_maps_flutter_pigeon_messages.g.h"

NS_ASSUME_NONNULL_BEGIN

/// The phases of one `updateMarkersByAdding:changing:removing:` batch that are timed separately.
typedef NS_ENUM(NSUInteger, FGMPerfPhase) {
  /// FGMIconFromBitmap for a FGMPlatformBitmapDefaultMarker (`[GMSMarker markerImageWithColor:]`).
  FGMPerfPhaseIconDefault = 0,
  /// FGMIconFromBitmap for a FGMPlatformBitmapAssetMap (`imageNamed:` + scaling).
  FGMPerfPhaseIconAsset,
  /// FGMIconFromBitmap for a FGMPlatformBitmapBytesMap (`imageWithData:` PNG decode + scaling).
  FGMPerfPhaseIconBytes,
  /// FGMIconFromBitmap for any other bitmap type (deprecated types, pin config).
  FGMPerfPhaseIconOther,
  /// `[GMSMarker markerWithPosition:]` / `[GMSAdvancedMarker markerWithPosition:]`.
  FGMPerfPhaseAlloc,
  /// `marker.map = mapView` (or `= nil` when invisible) at the end of `updateMarker:`.
  FGMPerfPhaseMapSet,
  /// `marker.map = nil` in `removeMarker`.
  FGMPerfPhaseMapNil,
  /// The remainder of `updateMarker:` (anchor, position, zIndex, rotation, info window, opacity),
  /// i.e. its wall time minus the icon and map-set phases.
  FGMPerfPhaseUpdateRest,
  /// Cluster manager work: `addItem:` / `removeItem:` per marker plus the final `cluster` call.
  FGMPerfPhaseCluster,
  /// The single refresh of the SDK's accessibility items after a batch (`FGM_OPT_AX_BATCH`).
  FGMPerfPhaseAccessibilityRefresh,
  FGMPerfPhaseCount
};

/// Whether `FGM_PERF=1` was set in the process environment. Evaluated once, then cached.
BOOL FGMPerfEnabled(void);

/// Monotonic time in seconds. Only meaningful when FGMPerfEnabled() is YES; returns 0 otherwise.
CFTimeInterval FGMPerfNow(void);

/// Marks the start of one marker batch and resets the per-batch accumulators.
void FGMPerfBeginBatch(NSUInteger toAdd, NSUInteger toChange, NSUInteger toRemove);

/// A batch that arrived while the previous one was still being applied in slices
/// (`FGM_OPT_CHUNKED_BATCH`). Its sizes are added to the batch in progress, which is logged as
/// one line when the last slice is done.
void FGMPerfMergeBatch(NSUInteger toAdd, NSUInteger toChange, NSUInteger toRemove);

/// Records one slice of a chunked batch: the stretch of the main thread from `startedAt` to now,
/// in which `operations` marker operations were carried out.
void FGMPerfRecordSlice(CFTimeInterval startedAt, NSUInteger operations);

/// Records the wall time of one of the three list passes (or the clustering pass) of the batch.
typedef NS_ENUM(NSUInteger, FGMPerfPass) {
  FGMPerfPassAdd = 0,
  FGMPerfPassChange,
  FGMPerfPassRemove,
  FGMPerfPassClusterInvoke,
  /// A marker that goes and a marker that comes done as one (`FGM_OPT_RECYCLE_MARKERS`). The
  /// icon and update_rest phases of such a pair are counted as for any marker.
  FGMPerfPassRecycle,
  FGMPerfPassCount
};
void FGMPerfRecordPass(FGMPerfPass pass, CFTimeInterval startedAt);

/// Adds `FGMPerfNow() - startedAt` to `phase` and increments its call count.
void FGMPerfAccumulateSince(FGMPerfPhase phase, CFTimeInterval startedAt);

/// Adds an already computed duration to `phase` (used for "rest of" measurements).
void FGMPerfAccumulate(FGMPerfPhase phase, CFTimeInterval seconds);

/// Maps a Pigeon bitmap to the icon phase it should be accounted under.
FGMPerfPhase FGMPerfIconPhaseForBitmap(FGMPlatformBitmap *_Nullable bitmap);

/// Ends the batch and logs one machine-readable line prefixed `[FGMPerf]`.
/// `totalMarkers` is the number of markers the controller holds after the batch.
void FGMPerfEndBatch(NSUInteger totalMarkers);

NS_ASSUME_NONNULL_END
