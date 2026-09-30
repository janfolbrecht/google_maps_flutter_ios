// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FGMMarkerController.h"
#import "FGMMarkerController_Test.h"

#import "FGMConversionUtils.h"
#import "FGMImageUtils.h"
#import "FGMMarkerBatchQueue.h"
#import "FGMMarkerUserData.h"
#import "FGMOptimizations.h"
#import "FGMPerf.h"

@interface FGMMarkerController ()

@property(strong, nonatomic, readwrite) GMSMarker *marker;
@property(weak, nonatomic) GMSMapView *mapView;
@property(assign, nonatomic, readwrite) BOOL consumeTapEvents;
/// The unique identifier for the cluster manager.
@property(copy, nonatomic, nullable) NSString *clusterManagerIdentifier;
/// The unique identifier for the marker.
@property(copy, nonatomic) NSString *markerIdentifier;

@end

@implementation FGMMarkerController

- (instancetype)initWithMarker:(GMSMarker *)marker
              markerIdentifier:(NSString *)markerIdentifier
                       mapView:(GMSMapView *)mapView {
  self = [super init];
  if (self) {
    _marker = marker;
    _markerIdentifier = [markerIdentifier copy];
    _mapView = mapView;
  }
  return self;
}

- (void)showInfoWindow {
  self.mapView.selectedMarker = self.marker;
}

- (void)hideInfoWindow {
  if (self.mapView.selectedMarker == self.marker) {
    self.mapView.selectedMarker = nil;
  }
}

- (BOOL)isInfoWindowShown {
  return self.mapView.selectedMarker == self.marker;
}

- (void)removeMarker {
  CFTimeInterval perfStart = FGMPerfNow();
  self.marker.map = nil;
  FGMPerfAccumulateSince(FGMPerfPhaseMapNil, perfStart);
}

- (void)updateFromPlatformMarker:(FGMPlatformMarker *)platformMarker
                   assetProvider:(NSObject<FGMAssetProvider> *)assetProvider
                     screenScale:(CGFloat)screenScale {
  self.clusterManagerIdentifier = platformMarker.clusterManagerId;
  self.consumeTapEvents = platformMarker.consumeTapEvents;

  // Set the marker's user data with current identifiers.
  FGMSetIdentifiersToMarkerUserData(self.markerIdentifier, self.clusterManagerIdentifier,
                                    self.marker);

  // If marker belongs the cluster manager, visibility need to be controlled with the opacity
  // as the cluster manager controls when marker is on the map and when not.
  BOOL useOpacityForVisibility = self.clusterManagerIdentifier != nil;
  [FGMMarkerController updateMarker:self.marker
                 fromPlatformMarker:platformMarker
                        withMapView:self.mapView
                      assetProvider:assetProvider
                        screenScale:screenScale
          usingOpacityForVisibility:useOpacityForVisibility];
}

+ (void)updateMarker:(GMSMarker *)marker
           fromPlatformMarker:(FGMPlatformMarker *)platformMarker
                  withMapView:(GMSMapView *)mapView
                assetProvider:(NSObject<FGMAssetProvider> *)assetProvider
                  screenScale:(CGFloat)screenScale
    usingOpacityForVisibility:(BOOL)useOpacityForVisibility {
  // FGMPerf: wall time of this method minus the icon and map-set phases is "update_rest".
  CFTimeInterval perfUpdateStart = FGMPerfNow();
  CFTimeInterval perfIconSeconds = 0;
  CFTimeInterval perfMapSetSeconds = 0;
  // RedMap fork, FGM_OPT_SKIP_UNCHANGED. The SDK logs a usage event in several of these setters
  // whatever the value, so a property that already holds the value is left alone. The order of
  // the setters is upstream's.
  BOOL setsAll = !FGMOptSkipUnchangedEnabled();
  CGPoint groundAnchor = FGMGetCGPointForPigeonPoint(platformMarker.anchor);
  if (setsAll || !CGPointEqualToPoint(marker.groundAnchor, groundAnchor)) {
    marker.groundAnchor = groundAnchor;
  }
  if (setsAll || marker.draggable != platformMarker.draggable) {
    marker.draggable = platformMarker.draggable;
  }
  CFTimeInterval perfIconStart = FGMPerfNow();
  UIImage *image = FGMIconFromBitmap(platformMarker.icon, assetProvider, screenScale);
  if (setsAll || marker.icon != image) {
    marker.icon = image;
  }
  if (FGMPerfEnabled()) {
    perfIconSeconds = FGMPerfNow() - perfIconStart;
    FGMPerfAccumulate(FGMPerfIconPhaseForBitmap(platformMarker.icon), perfIconSeconds);
  }
  if (setsAll || marker.flat != platformMarker.flat) {
    marker.flat = platformMarker.flat;
  }
  marker.position = FGMGetCoordinateForPigeonLatLng(platformMarker.position);
  if (setsAll || marker.rotation != platformMarker.rotation) {
    marker.rotation = platformMarker.rotation;
  }
  if (setsAll || marker.zIndex != (int)platformMarker.zIndex) {
    marker.zIndex = (int)platformMarker.zIndex;
  }
  FGMPlatformInfoWindow *infoWindow = platformMarker.infoWindow;
  CGPoint infoWindowAnchor = FGMGetCGPointForPigeonPoint(infoWindow.anchor);
  if (setsAll || !CGPointEqualToPoint(marker.infoWindowAnchor, infoWindowAnchor)) {
    marker.infoWindowAnchor = infoWindowAnchor;
  }
  if (infoWindow.title) {
    marker.title = infoWindow.title;
    marker.snippet = infoWindow.snippet;
  }

  if ([marker isKindOfClass:[GMSAdvancedMarker class]] && platformMarker.collisionBehavior != nil) {
    GMSCollisionBehavior collisionBehaviorValue =
        FGMGetCollisionBehaviorForPigeonCollisionBehavior(platformMarker.collisionBehavior.value);
    ((GMSAdvancedMarker *)marker).collisionBehavior = collisionBehaviorValue;
  }

  // This must be done last, to avoid visual flickers of default property values.
  if (useOpacityForVisibility) {
    marker.opacity = platformMarker.visible ? platformMarker.alpha : 0.0f;
  } else {
    float opacity = (float)platformMarker.alpha;
    if (setsAll || marker.opacity != opacity) {
      marker.opacity = opacity;
    }
    CFTimeInterval perfMapSetStart = FGMPerfNow();
    // A marker that is where it belongs is not attached or detached again: the SDK takes that
    // for an attach or a detach, with its usage event. A recycled marker depends on this.
    GMSMapView *map = platformMarker.visible ? mapView : nil;
    if ((setsAll && !FGMOptRecycleMarkersEnabled()) || marker.map != map) {
      marker.map = map;
    }
    if (FGMPerfEnabled()) {
      perfMapSetSeconds = FGMPerfNow() - perfMapSetStart;
      FGMPerfAccumulate(FGMPerfPhaseMapSet, perfMapSetSeconds);
    }
  }
  if (FGMPerfEnabled()) {
    FGMPerfAccumulate(FGMPerfPhaseUpdateRest,
                      FGMPerfNow() - perfUpdateStart - perfIconSeconds - perfMapSetSeconds);
  }
}

@end

@interface FGMMarkersController ()

@property(strong, nonatomic, readwrite)
    NSMutableDictionary<NSString *, FGMMarkerController *> *markerIdentifierToController;
@property(weak, nonatomic) NSObject<FGMMapEventDelegate> *eventDelegate;
/// Controller for adding/removing/fetching cluster managers
@property(weak, nonatomic, nullable) FGMClusterManagersController *clusterManagersController;
@property(strong, nonatomic) NSObject<FGMAssetProvider> *assetProvider;
@property(weak, nonatomic) GMSMapView *mapView;
@property(nonatomic) FGMPlatformMarkerType markerType;

// RedMap fork, FGM_OPT_CHUNKED_BATCH.
/// The operations of the batches that have come and are not applied yet.
@property(strong, nonatomic) FGMMarkerBatchQueue *waitingOperations;
/// Whether a slice is on its way through `sliceScheduler`.
@property(assign, nonatomic) BOOL sliceScheduled;
/// Whether the batch in progress hid the map's accessibility elements (FGM_OPT_AX_BATCH).
@property(assign, nonatomic) BOOL batchHidAccessibilityElements;
/// Runs one slice per frame when the pacing is `frame`; nil between batches.
@property(strong, nonatomic, nullable) CADisplayLink *sliceDisplayLink;
@property(assign, nonatomic, readwrite) CFTimeInterval sliceBudget;
@property(assign, nonatomic, readwrite) NSUInteger unsplitOperationLimit;
@property(copy, nonatomic, readwrite) void (^sliceScheduler)(dispatch_block_t slice);
@property(assign, nonatomic, readwrite) BOOL ordersNearestFirst;
@property(assign, nonatomic, readwrite) BOOL recyclesMarkers;

/// Runs the slice that `scheduleSlice` asked for.
- (void)runScheduledSlice;

@end

/// A batch of up to this many operations is applied whole within the call, as upstream does:
/// about 7 ms on an iPad (6th generation). What a tap on a pin sends is never split.
static const NSUInteger kFGMUnsplitOperationLimit = 50;

/// The target of the display link of the `frame` pacing, so that the link does not keep the
/// markers controller alive.
@interface FGMMarkerSliceTicker : NSObject
@property(weak, nonatomic) FGMMarkersController *controller;
@end

@implementation FGMMarkersController

- (instancetype)initWithMapView:(GMSMapView *)mapView
                  eventDelegate:(NSObject<FGMMapEventDelegate> *)eventDelegate
      clusterManagersController:(nullable FGMClusterManagersController *)clusterManagersController
                  assetProvider:(NSObject<FGMAssetProvider> *)assetProvider
                     markerType:(FGMPlatformMarkerType)markerType {
  self = [super init];
  if (self) {
    _eventDelegate = eventDelegate;
    _mapView = mapView;
    _clusterManagersController = clusterManagersController;
    _markerIdentifierToController = [[NSMutableDictionary alloc] init];
    _assetProvider = assetProvider;
    _markerType = markerType;
    _waitingOperations = [[FGMMarkerBatchQueue alloc] init];
    _sliceBudget = FGMOptChunkBudget();
    _unsplitOperationLimit = kFGMUnsplitOperationLimit;
    _ordersNearestFirst = FGMOptNearestFirstEnabled();
    _recyclesMarkers = FGMOptRecycleMarkersEnabled();
    _sliceScheduler = ^(dispatch_block_t slice) {
      dispatch_async(dispatch_get_main_queue(), slice);
    };
  }
  return self;
}

- (void)dealloc {
  [_sliceDisplayLink invalidate];
}

- (void)addMarkers:(NSArray<FGMPlatformMarker *> *)markersToAdd {
  for (FGMPlatformMarker *marker in markersToAdd) {
    [self addMarker:marker];
  }
}

- (void)addMarker:(FGMPlatformMarker *)markerToAdd {
  CLLocationCoordinate2D position = FGMGetCoordinateForPigeonLatLng(markerToAdd.position);
  NSString *markerIdentifier = markerToAdd.markerId;
  NSString *clusterManagerIdentifier = markerToAdd.clusterManagerId;
  CFTimeInterval perfAllocStart = FGMPerfNow();
  GMSMarker *marker = (self.markerType == FGMPlatformMarkerTypeAdvancedMarker)
                          ? [GMSAdvancedMarker markerWithPosition:position]
                          : [GMSMarker markerWithPosition:position];
  FGMPerfAccumulateSince(FGMPerfPhaseAlloc, perfAllocStart);
  FGMMarkerController *controller = [[FGMMarkerController alloc] initWithMarker:marker
                                                               markerIdentifier:markerIdentifier
                                                                        mapView:self.mapView];
  [controller updateFromPlatformMarker:markerToAdd
                         assetProvider:self.assetProvider
                           screenScale:[self getScreenScale]];
  if (clusterManagerIdentifier) {
    CFTimeInterval perfClusterStart = FGMPerfNow();
    GMUClusterManager *clusterManager =
        [_clusterManagersController clusterManagerWithIdentifier:clusterManagerIdentifier];
    if ([marker conformsToProtocol:@protocol(GMUClusterItem)]) {
      [clusterManager addItem:(id<GMUClusterItem>)marker];
    }
    FGMPerfAccumulateSince(FGMPerfPhaseCluster, perfClusterStart);
  }
  self.markerIdentifierToController[markerIdentifier] = controller;
}

- (void)changeMarkers:(NSArray<FGMPlatformMarker *> *)markersToChange {
  for (FGMPlatformMarker *marker in markersToChange) {
    [self changeMarker:marker];
  }
}

- (void)changeMarker:(FGMPlatformMarker *)markerToChange {
  NSString *markerIdentifier = markerToChange.markerId;

  FGMMarkerController *controller = self.markerIdentifierToController[markerIdentifier];
  if (!controller) {
    return;
  }

  NSString *clusterManagerIdentifier = markerToChange.clusterManagerId;
  NSString *previousClusterManagerIdentifier = [controller clusterManagerIdentifier];
  [controller updateFromPlatformMarker:markerToChange
                         assetProvider:self.assetProvider
                           screenScale:[self getScreenScale]];

  if ([controller.marker conformsToProtocol:@protocol(GMUClusterItem)]) {
    CFTimeInterval perfClusterStart = FGMPerfNow();
    if (previousClusterManagerIdentifier &&
        ![clusterManagerIdentifier isEqualToString:previousClusterManagerIdentifier]) {
      // Remove marker from previous cluster manager if its cluster manager identifier is removed or
      // changed.
      GMUClusterManager *clusterManager = [_clusterManagersController
          clusterManagerWithIdentifier:previousClusterManagerIdentifier];
      [clusterManager removeItem:(id<GMUClusterItem>)controller.marker];
    }

    if (clusterManagerIdentifier &&
        ![previousClusterManagerIdentifier isEqualToString:clusterManagerIdentifier]) {
      // Add marker to cluster manager if its cluster manager identifier has changed.
      GMUClusterManager *clusterManager =
          [_clusterManagersController clusterManagerWithIdentifier:clusterManagerIdentifier];
      [clusterManager addItem:(id<GMUClusterItem>)controller.marker];
    }
    FGMPerfAccumulateSince(FGMPerfPhaseCluster, perfClusterStart);
  }
}

- (void)removeMarkersWithIdentifiers:(NSArray<NSString *> *)identifiers {
  for (NSString *identifier in identifiers) {
    [self removeMarker:identifier];
  }
}

- (void)removeMarker:(NSString *)identifier {
  FGMMarkerController *controller = self.markerIdentifierToController[identifier];
  if (!controller) {
    return;
  }
  NSString *clusterManagerIdentifier = [controller clusterManagerIdentifier];
  if (clusterManagerIdentifier) {
    CFTimeInterval perfClusterStart = FGMPerfNow();
    GMUClusterManager *clusterManager =
        [_clusterManagersController clusterManagerWithIdentifier:clusterManagerIdentifier];
    [clusterManager removeItem:(id<GMUClusterItem>)controller.marker];
    FGMPerfAccumulateSince(FGMPerfPhaseCluster, perfClusterStart);
  } else {
    [controller removeMarker];
  }
  [self.markerIdentifierToController removeObjectForKey:identifier];
}

- (NSUInteger)markerCount {
  return self.markerIdentifierToController.count;
}

#pragma mark - RedMap fork, FGM_OPT_CHUNKED_BATCH

- (NSUInteger)waitingOperationCount {
  return self.waitingOperations.count;
}

- (void)updateMarkersInSlicesByAdding:(NSArray<FGMPlatformMarker *> *)toAdd
                             changing:(NSArray<FGMPlatformMarker *> *)toChange
                             removing:(NSArray<NSString *> *)idsToRemove {
  BOOL wasIdle = self.waitingOperations.count == 0;
  if (wasIdle) {
    FGMPerfBeginBatch(toAdd.count, toChange.count, idsToRemove.count);
  } else {
    FGMPerfMergeBatch(toAdd.count, toChange.count, idsToRemove.count);
    if (toAdd.count + toChange.count + idsToRemove.count == 0) {
      // The plugin is called on every rebuild of the widget. An empty batch has nothing to
      // hurry; the slices go on at their own pace.
      return;
    }
  }
  CFTimeInterval start = CACurrentMediaTime();
  [self.waitingOperations mergeBatchByAdding:toAdd
                                    changing:toChange
                                    removing:idsToRemove
                                 existsOnMap:^BOOL(NSString *identifier) {
                                   return self.markerIdentifierToController[identifier] != nil;
                                 }];
  NSUInteger waiting = self.waitingOperations.count;
  if (self.ordersNearestFirst && waiting > self.unsplitOperationLimit) {
    // FGM_OPT_NEAREST_FIRST. Everything that waits is ordered again, around where the camera
    // is now: what is left of an earlier batch was ordered around where it was then.
    [self.waitingOperations
        orderNearestFirstTo:self.mapView.camera.target
              positionOnMap:^CLLocationCoordinate2D(NSString *identifier) {
                FGMMarkerController *controller = self.markerIdentifierToController[identifier];
                return controller.marker.position;
              }];
  }
  if (wasIdle) {
    [self beginBatchInSlices:waiting > 0];
  }
  // A small batch that starts from an idle queue is applied whole. Otherwise one slice runs now,
  // so that the change a tap sends is on the screen when the call returns, and the rest follows.
  [self runSliceOfAtLeast:(wasIdle && waiting <= self.unsplitOperationLimit) ? waiting : 1
                startedAt:start];
}

/// What upstream does once before a batch. `hasWork` is NO for an empty batch, which leaves the
/// accessibility elements alone.
- (void)beginBatchInSlices:(BOOL)hasWork {
  GMSMapView *mapView = self.mapView;
  // FGM_OPT_AX_BATCH, as in the batch applied whole: the elements stay hidden until the last
  // slice is done. A map whose elements are hidden for good is left alone.
  self.batchHidAccessibilityElements =
      hasWork && FGMOptAccessibilityBatchEnabled() && !mapView.accessibilityElementsHidden;
  if (self.batchHidAccessibilityElements) {
    mapView.accessibilityElementsHidden = YES;
  }
}

/// What upstream does once after a batch: clustering, and the accessibility items.
- (void)endBatchInSlices {
  CFTimeInterval perfPassStart = FGMPerfNow();
  [self.clusterManagersController invokeClusteringForEachClusterManager];
  FGMPerfRecordPass(FGMPerfPassClusterInvoke, perfPassStart);
  FGMPerfAccumulateSince(FGMPerfPhaseCluster, perfPassStart);
  if (self.batchHidAccessibilityElements) {
    self.batchHidAccessibilityElements = NO;
    GMSMapView *mapView = self.mapView;
    mapView.accessibilityElementsHidden = NO;
    CFTimeInterval perfRefreshStart = FGMPerfNow();
    GMSMarker *refreshMarker = [[GMSMarker alloc] init];
    refreshMarker.map = mapView;
    refreshMarker.map = nil;
    FGMPerfAccumulateSince(FGMPerfPhaseAccessibilityRefresh, perfRefreshStart);
  }
  [self.sliceDisplayLink invalidate];
  self.sliceDisplayLink = nil;
}

/// Applies waiting operations until the slice budget, counted from `start`, is used up, and at
/// least `minimum` of them. Ends the batch when nothing is left, asks for the next slice
/// otherwise.
- (void)runSliceOfAtLeast:(NSUInteger)minimum startedAt:(CFTimeInterval)start {
  NSUInteger done = 0;
  while (self.waitingOperations.count > 0 &&
         (done < minimum || CACurrentMediaTime() - start < self.sliceBudget)) {
    done += [self applyNextWaitingOperation];
  }
  if (self.waitingOperations.count > 0) {
    FGMPerfRecordSlice(start, done);
    [self scheduleSlice];
    return;
  }
  [self endBatchInSlices];
  FGMPerfRecordSlice(start, done);
  FGMPerfEndBatch(self.markerCount);
}

/// Carries out the operation whose turn is next. Returns how many operations of the queue that
/// was: two when a removal and an addition were done as one recycled marker, one otherwise.
- (NSUInteger)applyNextWaitingOperation {
  FGMPlatformMarker *marker;
  NSString *identifier;
  FGMMarkerOperationKind kind = [self.waitingOperations takeNextOperationWithMarker:&marker
                                                                         identifier:&identifier];
  if (kind == FGMMarkerOperationKindRemove && self.recyclesMarkers) {
    FGMMarkerController *leaving = self.markerIdentifierToController[identifier];
    // Only a marker that is on the map itself can take another one's place, and only for one
    // that goes on the map itself: a marker of a cluster manager is put on the map and taken
    // off it by the manager.
    if (leaving.clusterManagerIdentifier == nil && leaving.marker.map != nil) {
      FGMPlatformMarker *arriving = [self.waitingOperations
          takeNextAdditionPassingTest:^BOOL(FGMPlatformMarker *candidate) {
            return candidate.clusterManagerId == nil && candidate.visible;
          }];
      if (arriving != nil) {
        [self recycleMarkerWithIdentifier:identifier forMarker:arriving];
        return 2;
      }
    }
  }
  [self applyOperation:kind marker:marker identifier:identifier];
  return 1;
}

/// FGM_OPT_RECYCLE_MARKERS. Removes the marker `identifier` and adds `arriving` in one: the
/// `GMSMarker` stays on the map and becomes the arriving marker. What is on the map afterwards is
/// what a removal and an addition would have left, without a detach, an allocation and an attach.
- (void)recycleMarkerWithIdentifier:(NSString *)identifier
                          forMarker:(FGMPlatformMarker *)arriving {
  CFTimeInterval perfPassStart = FGMPerfNow();
  GMSMapView *mapView = self.mapView;
  GMSMarker *marker = self.markerIdentifierToController[identifier].marker;
  [self.markerIdentifierToController removeObjectForKey:identifier];
  // What a removal does to the marker besides taking it off the map, and what a new marker
  // starts with where updateMarker: leaves a property alone.
  if (mapView.selectedMarker == marker) {
    mapView.selectedMarker = nil;
  }
  if (marker.title != nil) {
    marker.title = nil;
  }
  if (marker.snippet != nil) {
    marker.snippet = nil;
  }
  if ([marker isKindOfClass:[GMSAdvancedMarker class]]) {
    ((GMSAdvancedMarker *)marker).collisionBehavior = GMSCollisionBehaviorRequired;
  }
  FGMMarkerController *controller =
      [[FGMMarkerController alloc] initWithMarker:marker
                                 markerIdentifier:arriving.markerId
                                          mapView:mapView];
  // The position of a marker is animatable. The marker is another pin now, not one that moved.
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [CATransaction setAnimationDuration:0];
  [controller updateFromPlatformMarker:arriving
                         assetProvider:self.assetProvider
                           screenScale:[self getScreenScale]];
  [CATransaction commit];
  self.markerIdentifierToController[arriving.markerId] = controller;
  FGMPerfRecordPass(FGMPerfPassRecycle, perfPassStart);
}

- (void)applyOperation:(FGMMarkerOperationKind)kind
                marker:(nullable FGMPlatformMarker *)marker
            identifier:(nullable NSString *)identifier {
  CFTimeInterval perfPassStart = FGMPerfNow();
  switch (kind) {
    case FGMMarkerOperationKindChange:
      [self changeMarker:marker];
      FGMPerfRecordPass(FGMPerfPassChange, perfPassStart);
      break;
    case FGMMarkerOperationKindRemove:
      [self removeMarker:identifier];
      FGMPerfRecordPass(FGMPerfPassRemove, perfPassStart);
      break;
    case FGMMarkerOperationKindAdd:
      [self addMarker:marker];
      FGMPerfRecordPass(FGMPerfPassAdd, perfPassStart);
      break;
    case FGMMarkerOperationKindNone:
      break;
  }
}

- (void)scheduleSlice {
  if (FGMOptChunkPacingIsFrame()) {
    if (self.sliceDisplayLink == nil) {
      FGMMarkerSliceTicker *ticker = [[FGMMarkerSliceTicker alloc] init];
      ticker.controller = self;
      self.sliceDisplayLink = [CADisplayLink displayLinkWithTarget:ticker
                                                          selector:@selector(frame:)];
      [self.sliceDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    return;
  }
  if (self.sliceScheduled) {
    return;
  }
  self.sliceScheduled = YES;
  __weak typeof(self) weakSelf = self;
  self.sliceScheduler(^{
    [weakSelf runScheduledSlice];
  });
}

- (void)runScheduledSlice {
  self.sliceScheduled = NO;
  // A batch that came in the meantime may have finished the work within its own call.
  if (self.waitingOperations.count > 0) {
    [self runSliceOfAtLeast:1 startedAt:CACurrentMediaTime()];
  }
}

/// Carries out the waiting addition or change of one marker now, for a call that needs the
/// marker as the Dart side knows it. Ends the batch if it was the last operation waiting.
- (void)applyWaitingOperationForIdentifier:(NSString *)identifier {
  FGMPlatformMarker *marker;
  FGMMarkerOperationKind kind = [self.waitingOperations takeOperationForIdentifier:identifier
                                                                            marker:&marker];
  if (kind == FGMMarkerOperationKindNone) {
    return;
  }
  [self applyOperation:kind marker:marker identifier:identifier];
  if (self.waitingOperations.count == 0) {
    // It was the last one. The scheduled slice would find nothing to do, so the batch ends here.
    CFTimeInterval start = CACurrentMediaTime();
    [self endBatchInSlices];
    FGMPerfRecordSlice(start, 1);
    FGMPerfEndBatch(self.markerCount);
  }
}

/// The controller of a marker the Dart side knows: on the map and not waiting to be removed.
/// A marker whose addition is waiting is put on the map first.
- (nullable FGMMarkerController *)controllerKnownToDartWithIdentifier:(NSString *)identifier {
  if ([self.waitingOperations isWaitingToRemove:identifier]) {
    return nil;
  }
  [self applyWaitingOperationForIdentifier:identifier];
  return self.markerIdentifierToController[identifier];
}

#pragma mark -

- (BOOL)didTapMarkerWithIdentifier:(NSString *)identifier {
  if (!identifier) {
    return NO;
  }
  if ([self.waitingOperations isWaitingToRemove:identifier]) {
    // The Dart side has dropped this marker and would not know the tap. Consumed, so that the
    // SDK does not open the info window of a pin that is about to go.
    return YES;
  }
  FGMMarkerController *controller = self.markerIdentifierToController[identifier];
  if (!controller) {
    return NO;
  }
  [self.eventDelegate didTapMarkerWithIdentifier:identifier];
  return controller.consumeTapEvents;
}

- (void)didStartDraggingMarkerWithIdentifier:(NSString *)identifier
                                    location:(CLLocationCoordinate2D)location {
  if (!identifier) {
    return;
  }
  FGMMarkerController *controller = self.markerIdentifierToController[identifier];
  if (!controller || [self.waitingOperations isWaitingToRemove:identifier]) {
    return;
  }
  [self.eventDelegate
      didStartDragForMarkerWithIdentifier:identifier
                               atPosition:FGMGetPigeonLatLngForCoordinate(location)];
}

- (void)didDragMarkerWithIdentifier:(NSString *)identifier
                           location:(CLLocationCoordinate2D)location {
  if (!identifier) {
    return;
  }
  FGMMarkerController *controller = self.markerIdentifierToController[identifier];
  if (!controller || [self.waitingOperations isWaitingToRemove:identifier]) {
    return;
  }
  [self.eventDelegate didDragMarkerWithIdentifier:identifier
                                       atPosition:FGMGetPigeonLatLngForCoordinate(location)];
}

- (void)didEndDraggingMarkerWithIdentifier:(NSString *)identifier
                                  location:(CLLocationCoordinate2D)location {
  FGMMarkerController *controller = self.markerIdentifierToController[identifier];
  if (!controller || [self.waitingOperations isWaitingToRemove:identifier]) {
    return;
  }
  [self.eventDelegate didEndDragForMarkerWithIdentifier:identifier
                                             atPosition:FGMGetPigeonLatLngForCoordinate(location)];
}

- (void)didTapInfoWindowOfMarkerWithIdentifier:(NSString *)identifier {
  if (identifier && self.markerIdentifierToController[identifier] &&
      ![self.waitingOperations isWaitingToRemove:identifier]) {
    [self.eventDelegate didTapInfoWindowOfMarkerWithIdentifier:identifier];
  }
}

- (void)showMarkerInfoWindowWithIdentifier:(NSString *)identifier
                                     error:
                                         (FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  FGMMarkerController *controller = [self controllerKnownToDartWithIdentifier:identifier];
  if (controller) {
    [controller showInfoWindow];
  } else {
    *error = [FlutterError errorWithCode:@"Invalid markerId"
                                 message:@"showInfoWindow called with invalid markerId"
                                 details:nil];
  }
}

- (void)hideMarkerInfoWindowWithIdentifier:(NSString *)identifier
                                     error:
                                         (FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  FGMMarkerController *controller = [self controllerKnownToDartWithIdentifier:identifier];
  if (controller) {
    [controller hideInfoWindow];
  } else {
    *error = [FlutterError errorWithCode:@"Invalid markerId"
                                 message:@"hideInfoWindow called with invalid markerId"
                                 details:nil];
  }
}

- (nullable NSNumber *)
    isInfoWindowShownForMarkerWithIdentifier:(NSString *)identifier
                                       error:(FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                 error {
  FGMMarkerController *controller = [self controllerKnownToDartWithIdentifier:identifier];
  if (controller) {
    return @([controller isInfoWindowShown]);
  } else {
    *error = [FlutterError errorWithCode:@"Invalid markerId"
                                 message:@"isInfoWindowShown called with invalid markerId"
                                 details:nil];
    return nil;
  }
}

- (CGFloat)getScreenScale {
  // TODO(jokerttu): This method is called on marker creation, which, for initial markers, is done
  // before the view is added to the view hierarchy. This means that the traitCollection values may
  // not be matching the right display where the map is finally shown. The solution should be
  // revisited after the proper way to fetch the display scale is resolved for platform views. This
  // should be done under the context of the following issue:
  // https://github.com/flutter/flutter/issues/125496.
  return self.mapView.traitCollection.displayScale;
}

@end

@implementation FGMMarkerSliceTicker

- (void)frame:(CADisplayLink *)link {
  FGMMarkersController *controller = self.controller;
  if (controller == nil) {
    [link invalidate];
    return;
  }
  [controller runScheduledSlice];
}

@end
