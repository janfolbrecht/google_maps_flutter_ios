// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition (https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/69).
//
// Runtime switches of the fork's optimisations of the marker path. Each one is on by default and
// is switched off by setting its process environment variable to `0`, which restores the upstream
// behaviour. A variable is read once, on first use.

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

/// `FGM_OPT_AX_BATCH`: hide the map's accessibility elements for the length of a marker batch, so
/// that the SDK rebuilds its accessibility items once per batch instead of once per marker.
BOOL FGMOptAccessibilityBatchEnabled(void);

/// `FGM_OPT_ICON_CACHE`: keep the image made from a bitmap descriptor and hand the same `UIImage`
/// to every marker that asks for an equal descriptor, instead of making it again per marker.
BOOL FGMOptIconCacheEnabled(void);

/// `FGM_OPT_ICON_DESCRIPTION`: a cached icon answers `-description` with a string made once.
/// When the SDK draws a marker that is new or has changed it asks the marker's image for its
/// description, and `UIImage` formats that string anew on every call; with a thousand markers
/// changed in a pan that was a third of the SDK's drawing. Needs `FGM_OPT_ICON_CACHE`.
BOOL FGMOptIconDescriptionEnabled(void);

/// `FGM_OPT_CHUNKED_BATCH`: apply a marker batch in slices of a few milliseconds, one per frame of
/// the display, so that the map answers touches and draws while the markers arrive, instead of
/// in one piece on the main thread.
BOOL FGMOptChunkedBatchEnabled(void);

/// `FGM_OPT_NEAREST_FIRST`: within a chunked batch, carry out the removals and the additions in
/// the order of their distance from the centre of the map, nearest first, so that what the user
/// looks at is finished first. Off, they keep the order the Dart side sent them in.
BOOL FGMOptNearestFirstEnabled(void);

/// `FGM_OPT_RECYCLE_MARKERS`: within a chunked batch, a marker that goes and a marker that comes
/// are one operation: the `GMSMarker` of the first stays on the map and takes the identifier and
/// the properties of the second. Detaching a marker, making one and attaching it cost several
/// times what moving one costs, most of it in the SDK's own usage log, which writes to the user
/// defaults on every attach and detach.
BOOL FGMOptRecycleMarkersEnabled(void);

/// `FGM_OPT_SKIP_UNCHANGED`: when a marker is updated, a property that already holds the value
/// is not set again, and a marker that is on the map is not attached to it again. The SDK logs a
/// usage event for several of the setters whatever the value.
BOOL FGMOptSkipUnchangedEnabled(void);

/// `FGM_OPT_CHUNK_BUDGET_MS`: the time one slice of a chunked batch may take, in seconds. 8 ms
/// unless the variable holds another positive number of milliseconds. A knob for measuring.
CFTimeInterval FGMOptChunkBudget(void);

/// `FGM_OPT_CHUNK_PACING`: when the slices of a chunked batch run. `frame`, the default: one slice
/// per frame of the display, so that the SDK never has more than one slice of changed markers to
/// draw in a frame. `queue`: one slice per turn of the main queue, which puts two or three slices
/// between two frames and makes those frames long. A knob for measuring.
BOOL FGMOptChunkPacingIsFrame(void);

NS_ASSUME_NONNULL_END
