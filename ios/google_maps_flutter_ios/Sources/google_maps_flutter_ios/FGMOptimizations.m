// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition (https://github.com/redmapapp-tim/cfan_redmap_flutter/issues/69).
// See FGMOptimizations.h for the contract.

#import "FGMOptimizations.h"

static BOOL FGMOptIsOn(NSString *name) {
  return ![NSProcessInfo.processInfo.environment[name] isEqualToString:@"0"];
}

BOOL FGMOptAccessibilityBatchEnabled(void) {
  static BOOL enabled;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    enabled = FGMOptIsOn(@"FGM_OPT_AX_BATCH");
  });
  return enabled;
}
