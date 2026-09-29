// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition (https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/69).
// See FGMPerf.h for the contract.

#import "FGMPerf.h"

#import "FGMOptimizations.h"

// Per-batch accumulators. The plugin touches markers only on the main thread (a GoogleMaps SDK
// requirement), so plain statics are sufficient; no locking.
static CFTimeInterval gPhaseSeconds[FGMPerfPhaseCount];
static NSUInteger gPhaseCalls[FGMPerfPhaseCount];
static CFTimeInterval gPassSeconds[FGMPerfPassCount];
static CFTimeInterval gBatchStart;
static CFTimeInterval gPreviousBatchEnd;
static NSUInteger gBatchSequence;
static NSUInteger gToAdd, gToChange, gToRemove;

BOOL FGMPerfEnabled(void) {
  static BOOL enabled = NO;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *value = NSProcessInfo.processInfo.environment[@"FGM_PERF"];
    enabled = [value isEqualToString:@"1"];
    if (enabled) {
      NSLog(@"[FGMPerf] enabled=1 clock=CACurrentMediaTime units=ms opt_ax_batch=%d",
            FGMOptAccessibilityBatchEnabled());
    }
  });
  return enabled;
}

CFTimeInterval FGMPerfNow(void) {
  return FGMPerfEnabled() ? CACurrentMediaTime() : 0;
}

void FGMPerfBeginBatch(NSUInteger toAdd, NSUInteger toChange, NSUInteger toRemove) {
  if (!FGMPerfEnabled()) {
    return;
  }
  memset(gPhaseSeconds, 0, sizeof(gPhaseSeconds));
  memset(gPhaseCalls, 0, sizeof(gPhaseCalls));
  memset(gPassSeconds, 0, sizeof(gPassSeconds));
  gToAdd = toAdd;
  gToChange = toChange;
  gToRemove = toRemove;
  gBatchSequence += 1;
  gBatchStart = CACurrentMediaTime();
}

void FGMPerfRecordPass(FGMPerfPass pass, CFTimeInterval startedAt) {
  if (!FGMPerfEnabled()) {
    return;
  }
  gPassSeconds[pass] += CACurrentMediaTime() - startedAt;
}

void FGMPerfAccumulateSince(FGMPerfPhase phase, CFTimeInterval startedAt) {
  if (!FGMPerfEnabled()) {
    return;
  }
  gPhaseSeconds[phase] += CACurrentMediaTime() - startedAt;
  gPhaseCalls[phase] += 1;
}

void FGMPerfAccumulate(FGMPerfPhase phase, CFTimeInterval seconds) {
  if (!FGMPerfEnabled()) {
    return;
  }
  gPhaseSeconds[phase] += seconds;
  gPhaseCalls[phase] += 1;
}

FGMPerfPhase FGMPerfIconPhaseForBitmap(FGMPlatformBitmap *bitmap) {
  id inner = bitmap.bitmap;
  if ([inner isKindOfClass:[FGMPlatformBitmapDefaultMarker class]]) {
    return FGMPerfPhaseIconDefault;
  }
  if ([inner isKindOfClass:[FGMPlatformBitmapAssetMap class]]) {
    return FGMPerfPhaseIconAsset;
  }
  if ([inner isKindOfClass:[FGMPlatformBitmapBytesMap class]]) {
    return FGMPerfPhaseIconBytes;
  }
  return FGMPerfPhaseIconOther;
}

static double FGMPerfMilliseconds(CFTimeInterval seconds) { return seconds * 1000.0; }

void FGMPerfEndBatch(NSUInteger totalMarkers) {
  if (!FGMPerfEnabled()) {
    return;
  }
  CFTimeInterval end = CACurrentMediaTime();
  CFTimeInterval total = end - gBatchStart;
  // Milliseconds since the previous batch finished; -1 for the first batch. A run of short gaps
  // means Dart pushed the pan as several updates rather than one.
  double gapMs = gPreviousBatchEnd > 0 ? FGMPerfMilliseconds(gBatchStart - gPreviousBatchEnd) : -1;
  gPreviousBatchEnd = end;

  CFTimeInterval accounted = 0;
  for (NSUInteger i = 0; i < FGMPerfPhaseCount; i++) {
    accounted += gPhaseSeconds[i];
  }

  // One line, key=value, fixed key order, so it can be grepped and summed with a script.
  NSLog(@"[FGMPerf] batch=%lu total_ms=%.2f gap_ms=%.2f add=%lu change=%lu remove=%lu "
        @"markers=%lu "
        @"pass_add_ms=%.2f pass_change_ms=%.2f pass_remove_ms=%.2f pass_cluster_ms=%.2f "
        @"icon_default_ms=%.2f icon_default_n=%lu "
        @"icon_asset_ms=%.2f icon_asset_n=%lu "
        @"icon_bytes_ms=%.2f icon_bytes_n=%lu "
        @"icon_other_ms=%.2f icon_other_n=%lu "
        @"alloc_ms=%.2f alloc_n=%lu "
        @"map_set_ms=%.2f map_set_n=%lu "
        @"map_nil_ms=%.2f map_nil_n=%lu "
        @"update_rest_ms=%.2f update_rest_n=%lu "
        @"cluster_ms=%.2f cluster_n=%lu "
        @"unaccounted_ms=%.2f "
        @"ax_refresh_ms=%.2f ax_refresh_n=%lu",
        (unsigned long)gBatchSequence, FGMPerfMilliseconds(total), gapMs, (unsigned long)gToAdd,
        (unsigned long)gToChange, (unsigned long)gToRemove, (unsigned long)totalMarkers,
        FGMPerfMilliseconds(gPassSeconds[FGMPerfPassAdd]),
        FGMPerfMilliseconds(gPassSeconds[FGMPerfPassChange]),
        FGMPerfMilliseconds(gPassSeconds[FGMPerfPassRemove]),
        FGMPerfMilliseconds(gPassSeconds[FGMPerfPassClusterInvoke]),
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseIconDefault]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseIconDefault],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseIconAsset]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseIconAsset],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseIconBytes]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseIconBytes],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseIconOther]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseIconOther],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseAlloc]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseAlloc],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseMapSet]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseMapSet],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseMapNil]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseMapNil],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseUpdateRest]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseUpdateRest],
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseCluster]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseCluster],
        FGMPerfMilliseconds(total - accounted),
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseAccessibilityRefresh]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseAccessibilityRefresh]);
}
