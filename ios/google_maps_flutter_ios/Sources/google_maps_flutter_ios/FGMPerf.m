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
static NSUInteger gPassCalls[FGMPerfPassCount];
static CFTimeInterval gBatchStart;
static CFTimeInterval gPreviousBatchEnd;
static NSUInteger gBatchSequence;
static NSUInteger gToAdd, gToChange, gToRemove;
// Slices of a chunked batch, and what the display link saw between its begin and its end.
static NSUInteger gSlices, gSliceOperations, gMergedBatches;
static CFTimeInterval gSliceSeconds, gLongestSlice;
static BOOL gBatchInProgress;
static NSUInteger gFramesInBatch;
static CFTimeInterval gLongestFrameGapInBatch;

/// A gap between two callbacks of the display link from which on it is logged: two frames of a
/// 60 Hz display.
static const CFTimeInterval kFGMPerfHitchThreshold = 0.034;

/// Watches the main thread with a display link. The link fires once per frame as long as the
/// main run loop turns, so the time between two callbacks is how long the main thread was busy
/// with something else.
@interface FGMPerfFrameMonitor : NSObject
@end

@implementation FGMPerfFrameMonitor {
  CFTimeInterval _previousCallback;
}

+ (void)start {
  dispatch_async(dispatch_get_main_queue(), ^{
    static FGMPerfFrameMonitor *monitor;
    if (monitor != nil) {
      return;
    }
    monitor = [[FGMPerfFrameMonitor alloc] init];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:monitor selector:@selector(frame:)];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  });
}

- (void)frame:(CADisplayLink *)link {
  CFTimeInterval now = CACurrentMediaTime();
  if (_previousCallback > 0) {
    CFTimeInterval gap = now - _previousCallback;
    if (gBatchInProgress) {
      gFramesInBatch += 1;
      if (gap > gLongestFrameGapInBatch) {
        gLongestFrameGapInBatch = gap;
      }
    }
    if (gap >= kFGMPerfHitchThreshold) {
      // t_end is on the clock of t_begin and t_end of the batch lines.
      NSLog(@"[FGMPerf] hitch gap_ms=%.1f t_end=%.4f", gap * 1000.0, now);
    }
  }
  _previousCallback = now;
}

@end

BOOL FGMPerfEnabled(void) {
  static BOOL enabled = NO;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *value = NSProcessInfo.processInfo.environment[@"FGM_PERF"];
    enabled = [value isEqualToString:@"1"];
    if (enabled) {
      NSLog(@"[FGMPerf] enabled=1 clock=CACurrentMediaTime units=ms opt_ax_batch=%d "
            @"opt_icon_cache=%d opt_chunked_batch=%d opt_nearest_first=%d opt_recycle_markers=%d "
            @"opt_skip_unchanged=%d chunk_budget_ms=%.1f chunk_pacing=%@",
            FGMOptAccessibilityBatchEnabled(), FGMOptIconCacheEnabled(),
            FGMOptChunkedBatchEnabled(), FGMOptNearestFirstEnabled(),
            FGMOptRecycleMarkersEnabled(), FGMOptSkipUnchangedEnabled(),
            FGMOptChunkBudget() * 1000.0,
            FGMOptChunkPacingIsFrame() ? @"frame" : @"queue");
      [FGMPerfFrameMonitor start];
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
  memset(gPassCalls, 0, sizeof(gPassCalls));
  gToAdd = toAdd;
  gToChange = toChange;
  gToRemove = toRemove;
  gSlices = 0;
  gSliceOperations = 0;
  gMergedBatches = 0;
  gSliceSeconds = 0;
  gLongestSlice = 0;
  gFramesInBatch = 0;
  gLongestFrameGapInBatch = 0;
  gBatchInProgress = YES;
  gBatchSequence += 1;
  gBatchStart = CACurrentMediaTime();
}

void FGMPerfMergeBatch(NSUInteger toAdd, NSUInteger toChange, NSUInteger toRemove) {
  if (!FGMPerfEnabled()) {
    return;
  }
  gToAdd += toAdd;
  gToChange += toChange;
  gToRemove += toRemove;
  gMergedBatches += 1;
}

void FGMPerfRecordSlice(CFTimeInterval startedAt, NSUInteger operations) {
  if (!FGMPerfEnabled()) {
    return;
  }
  CFTimeInterval seconds = CACurrentMediaTime() - startedAt;
  gSlices += 1;
  gSliceOperations += operations;
  gSliceSeconds += seconds;
  if (seconds > gLongestSlice) {
    gLongestSlice = seconds;
  }
}

void FGMPerfRecordPass(FGMPerfPass pass, CFTimeInterval startedAt) {
  if (!FGMPerfEnabled()) {
    return;
  }
  gPassSeconds[pass] += CACurrentMediaTime() - startedAt;
  gPassCalls[pass] += 1;
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
  gBatchInProgress = NO;
  // A batch applied in one piece is one slice as long as the batch.
  if (gSlices == 0) {
    gSlices = 1;
    gSliceOperations = gToAdd + gToChange + gToRemove;
    gSliceSeconds = total;
    gLongestSlice = total;
  }

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
        @"ax_refresh_ms=%.2f ax_refresh_n=%lu "
        @"slices=%lu slice_ops=%lu work_ms=%.2f max_slice_ms=%.2f merged=%lu "
        @"frames=%lu max_frame_gap_ms=%.2f t_begin=%.4f t_end=%.4f "
        @"recycled=%lu pass_recycle_ms=%.2f",
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
        FGMPerfMilliseconds(gSliceSeconds - accounted),
        FGMPerfMilliseconds(gPhaseSeconds[FGMPerfPhaseAccessibilityRefresh]),
        (unsigned long)gPhaseCalls[FGMPerfPhaseAccessibilityRefresh], (unsigned long)gSlices,
        (unsigned long)gSliceOperations, FGMPerfMilliseconds(gSliceSeconds),
        FGMPerfMilliseconds(gLongestSlice), (unsigned long)gMergedBatches,
        (unsigned long)gFramesInBatch, FGMPerfMilliseconds(gLongestFrameGapInBatch), gBatchStart,
        end, (unsigned long)gPassCalls[FGMPerfPassRecycle],
        FGMPerfMilliseconds(gPassSeconds[FGMPerfPassRecycle]));
}
