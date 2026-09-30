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

/// `FGM_OPT_CHUNKED_BATCH`: apply a marker batch in slices of a few milliseconds with the run loop
/// turning between them, so that the map answers touches and draws while the markers arrive,
/// instead of in one piece on the main thread.
BOOL FGMOptChunkedBatchEnabled(void);

/// `FGM_OPT_NEAREST_FIRST`: within a chunked batch, carry out the removals and the additions in
/// the order of their distance from the centre of the map, nearest first, so that what the user
/// looks at is finished first. Off, they keep the order the Dart side sent them in.
BOOL FGMOptNearestFirstEnabled(void);

/// `FGM_OPT_CHUNK_BUDGET_MS`: the time one slice of a chunked batch may take, in seconds. 8 ms
/// unless the variable holds another positive number of milliseconds. A knob for measuring.
CFTimeInterval FGMOptChunkBudget(void);

/// `FGM_OPT_CHUNK_PACING=frame`: run one slice per frame of the display instead of one per turn
/// of the main queue. A knob for measuring; the default is the main queue.
BOOL FGMOptChunkPacingIsFrame(void);

NS_ASSUME_NONNULL_END
