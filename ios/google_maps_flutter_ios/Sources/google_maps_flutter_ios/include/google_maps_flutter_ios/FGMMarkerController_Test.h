// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FGMMarkerController.h"

/// Methods exposed for unit testing.
@interface FGMMarkerController (Test)

/// The underlying controlled GMSMarker.
@property(strong, nonatomic, readonly) GMSMarker *marker;

/// Updates the underlying GMSMarker with the properties from the given FGMPlatformMarker.
///
/// Setting the marker to visible will set its map to the given mapView.
+ (void)updateMarker:(GMSMarker *)marker
           fromPlatformMarker:(FGMPlatformMarker *)platformMarker
                  withMapView:(GMSMapView *)mapView
                assetProvider:(NSObject<FGMAssetProvider> *)assetProvider
                  screenScale:(CGFloat)screenScale
    usingOpacityForVisibility:(BOOL)useOpacityForVisibility;

@end

/// Methods exposed for unit testing.
@interface FGMMarkersController (Test)

/// A mapping from marker identifiers to corresponding marker controllers.
@property(strong, nonatomic, readonly) NSMutableDictionary *markerIdentifierToController;

// RedMap fork, FGM_OPT_CHUNKED_BATCH.

/// The time one slice of a batch may take, in seconds. Zero makes every slice one operation.
@property(assign, nonatomic) CFTimeInterval sliceBudget;

/// A batch of up to this many operations that finds nothing waiting is applied whole.
@property(assign, nonatomic) NSUInteger unsplitOperationLimit;

/// Whether the removals and the additions of a batch that is split are carried out nearest to
/// the centre of the map first (FGM_OPT_NEAREST_FIRST, which this starts from).
@property(assign, nonatomic) BOOL ordersNearestFirst;

/// Whether a marker that goes and a marker that comes in a batch are done as one, the
/// `GMSMarker` staying on the map (FGM_OPT_RECYCLE_MARKERS, which this starts from).
@property(assign, nonatomic) BOOL recyclesMarkers;

/// Gets the block that runs the next slice and has to run it later. Nil by default: the slices
/// then run one per frame of the display. A test keeps the block and runs it when it wants the
/// next slice.
@property(copy, nonatomic) void (^sliceScheduler)(dispatch_block_t slice);

@end
