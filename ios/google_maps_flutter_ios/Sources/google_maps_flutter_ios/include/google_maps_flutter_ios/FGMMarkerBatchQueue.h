// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition, FGM_OPT_CHUNKED_BATCH.
//
// The marker operations of the batches the Dart side has sent and the plugin has not applied
// yet. The Dart side computes every batch against the set of markers it sent before, so the
// batches have to add up to the same markers on the map as if each had been applied whole, in
// the order they came. The queue keeps that promise while a later batch overtakes an earlier one:
// an operation that a later batch undoes is dropped instead of being carried out and reverted.

@import CoreLocation;
@import Foundation;

#import "google_maps_flutter_pigeon_messages.g.h"

NS_ASSUME_NONNULL_BEGIN

/// What `takeNextOperation...` handed out.
typedef NS_ENUM(NSUInteger, FGMMarkerOperationKind) {
  /// Nothing is waiting.
  FGMMarkerOperationKindNone = 0,
  /// A marker on the map takes new properties; `marker` is set.
  FGMMarkerOperationKindChange,
  /// A marker on the map goes; `identifier` is set.
  FGMMarkerOperationKindRemove,
  /// A marker that is not on the map comes; `marker` is set.
  FGMMarkerOperationKindAdd,
};

@interface FGMMarkerBatchQueue : NSObject

/// The number of operations waiting.
@property(nonatomic, readonly) NSUInteger count;

/// Takes a batch in. `existsOnMap` says whether the plugin holds a marker with an identifier
/// now, that is, without the operations waiting here.
///
/// The lists are merged in the order upstream applies them: additions, changes, removals.
/// - A removal of a marker whose addition is waiting drops the addition.
/// - An addition of a marker whose removal is waiting drops the removal and changes the marker.
/// - A change of a marker whose addition is waiting replaces the marker to add.
/// - A change or a removal of a marker that is neither on the map nor waiting is ignored, as
///   upstream ignores it.
- (void)mergeBatchByAdding:(NSArray<FGMPlatformMarker *> *)toAdd
                  changing:(NSArray<FGMPlatformMarker *> *)toChange
                  removing:(NSArray<NSString *> *)idsToRemove
               existsOnMap:(BOOL (NS_NOESCAPE ^)(NSString *identifier))existsOnMap;

/// FGM_OPT_NEAREST_FIRST. Puts the waiting removals and the waiting additions into the order of
/// their distance from `centre`, nearest first; operations equally far keep the order they had.
/// `positionOnMap` gives the position of a marker that is on the map, for the removals.
/// The order holds until the next batch is merged, which appends what it brings.
- (void)orderNearestFirstTo:(CLLocationCoordinate2D)centre
              positionOnMap:(CLLocationCoordinate2D (NS_NOESCAPE ^)(NSString *identifier))positionOnMap;

/// Hands out the next operation and forgets it.
///
/// Changes come first: they are what a tap on a pin sends, and the pin they belong to is on the
/// screen. Removals and additions then take turns, a removal first, so that the number of markers
/// on the map never rises above the larger of the number before the batch and the number after
/// it, and the new pins start to appear with the first slice.
- (FGMMarkerOperationKind)takeNextOperationWithMarker:
                              (FGMPlatformMarker *_Nullable __autoreleasing *_Nonnull)marker
                                           identifier:(NSString *_Nullable __autoreleasing *_Nonnull)
                                                          identifier;

/// FGM_OPT_RECYCLE_MARKERS. Hands out the addition whose turn is next, and forgets it, if there
/// is one and `test` accepts it; nil otherwise, and the addition keeps its turn. For the marker
/// that takes the place of one whose removal was just handed out.
- (nullable FGMPlatformMarker *)takeNextAdditionPassingTest:
    (BOOL (NS_NOESCAPE ^)(FGMPlatformMarker *marker))test;

/// Hands out the waiting addition or change of one marker ahead of its turn, for a call that
/// needs that marker on the map as the Dart side knows it (an info window to show).
- (FGMMarkerOperationKind)takeOperationForIdentifier:(NSString *)identifier
                                              marker:(FGMPlatformMarker *_Nullable __autoreleasing
                                                          *_Nonnull)marker;

/// Whether the removal of a marker is waiting. Such a marker is still on the map, and the Dart
/// side no longer knows it.
- (BOOL)isWaitingToRemove:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
