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

NS_ASSUME_NONNULL_END
