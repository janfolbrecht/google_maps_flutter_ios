// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// RedMap fork addition, FGM_OPT_CHUNKED_BATCH. See FGMMarkerBatchQueue.h for the contract.

#import "FGMMarkerBatchQueue.h"

@implementation FGMMarkerBatchQueue {
  // The dictionaries and the set say what is waiting. The arrays only give the order: an
  // identifier in an array that is no longer in its dictionary or set was dropped by a later
  // batch and is skipped when its turn comes.
  NSMutableDictionary<NSString *, FGMPlatformMarker *> *_additions;
  NSMutableDictionary<NSString *, FGMPlatformMarker *> *_changes;
  NSMutableSet<NSString *> *_removals;
  NSMutableArray<NSString *> *_additionOrder;
  NSMutableArray<NSString *> *_changeOrder;
  NSMutableArray<NSString *> *_removalOrder;
  NSUInteger _additionCursor;
  NSUInteger _changeCursor;
  NSUInteger _removalCursor;
  // Additions handed out minus removals handed out since the queue was last empty.
  NSInteger _balance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _additions = [[NSMutableDictionary alloc] init];
    _changes = [[NSMutableDictionary alloc] init];
    _removals = [[NSMutableSet alloc] init];
    _additionOrder = [[NSMutableArray alloc] init];
    _changeOrder = [[NSMutableArray alloc] init];
    _removalOrder = [[NSMutableArray alloc] init];
  }
  return self;
}

- (NSUInteger)count {
  return _additions.count + _changes.count + _removals.count;
}

- (void)mergeBatchByAdding:(NSArray<FGMPlatformMarker *> *)toAdd
                  changing:(NSArray<FGMPlatformMarker *> *)toChange
                  removing:(NSArray<NSString *> *)idsToRemove
               existsOnMap:(BOOL (NS_NOESCAPE ^)(NSString *identifier))existsOnMap {
  for (FGMPlatformMarker *marker in toAdd) {
    NSString *identifier = marker.markerId;
    if ([_removals containsObject:identifier]) {
      // Going and coming back: the marker stays and takes the properties it comes back with.
      [_removals removeObject:identifier];
      [self setChange:marker];
    } else if (_additions[identifier] == nil && existsOnMap(identifier)) {
      // Upstream would put a second marker on the map under the same identifier and lose the
      // first one for good. The Dart side never sends this; if it did, one marker is right.
      [self setChange:marker];
    } else {
      if (_additions[identifier] == nil) {
        [_additionOrder addObject:identifier];
      }
      _additions[identifier] = marker;
    }
  }
  for (FGMPlatformMarker *marker in toChange) {
    NSString *identifier = marker.markerId;
    if (_additions[identifier] != nil) {
      _additions[identifier] = marker;
    } else if (![_removals containsObject:identifier] && existsOnMap(identifier)) {
      [self setChange:marker];
    }
  }
  for (NSString *identifier in idsToRemove) {
    if (_additions[identifier] != nil) {
      [_additions removeObjectForKey:identifier];
    } else if (![_removals containsObject:identifier] && existsOnMap(identifier)) {
      [_changes removeObjectForKey:identifier];
      [_removals addObject:identifier];
      [_removalOrder addObject:identifier];
    }
  }
  [self resetIfEmpty];
}

- (void)setChange:(FGMPlatformMarker *)marker {
  NSString *identifier = marker.markerId;
  if (_changes[identifier] == nil) {
    [_changeOrder addObject:identifier];
  }
  _changes[identifier] = marker;
}

/// The square of the distance between two positions in degrees, the longitude shortened to the
/// latitude of `centre` and taken the short way round the globe. Only for comparing.
static double FGMSquaredDistance(CLLocationCoordinate2D centre, CLLocationCoordinate2D position) {
  double latitude = position.latitude - centre.latitude;
  double longitude = fabs(position.longitude - centre.longitude);
  if (longitude > 180.0) {
    longitude = 360.0 - longitude;
  }
  longitude *= cos(centre.latitude * M_PI / 180.0);
  return latitude * latitude + longitude * longitude;
}

- (void)orderNearestFirstTo:(CLLocationCoordinate2D)centre
              positionOnMap:
                  (CLLocationCoordinate2D (NS_NOESCAPE ^)(NSString *identifier))positionOnMap {
  NSDictionary<NSString *, FGMPlatformMarker *> *additions = _additions;
  _additionOrder = [self identifiersWaitingIn:_additionOrder
                                         from:_additionCursor
                                      waiting:_additions
                                   sortedByKey:^double(NSString *identifier) {
                                     FGMPlatformLatLng *position = additions[identifier].position;
                                     return FGMSquaredDistance(
                                         centre, CLLocationCoordinate2DMake(position.latitude,
                                                                            position.longitude));
                                   }];
  _additionCursor = 0;
  _removalOrder = [self identifiersWaitingIn:_removalOrder
                                        from:_removalCursor
                                     waiting:_removals
                                  sortedByKey:^double(NSString *identifier) {
                                    return FGMSquaredDistance(centre, positionOnMap(identifier));
                                  }];
  _removalCursor = 0;
}

/// The identifiers of `order` from `cursor` on that are still waiting, each once, sorted by
/// `key` ascending; equal keys keep their order.
- (NSMutableArray<NSString *> *)identifiersWaitingIn:(NSArray<NSString *> *)order
                                                from:(NSUInteger)cursor
                                             waiting:(id)waiting
                                         sortedByKey:(double (NS_NOESCAPE ^)(NSString *identifier))key {
  NSMutableArray<NSString *> *identifiers = [[NSMutableArray alloc] init];
  NSMutableSet<NSString *> *seen = [[NSMutableSet alloc] init];
  for (NSUInteger i = cursor; i < order.count; i++) {
    NSString *identifier = order[i];
    if ([self isIdentifier:identifier waitingIn:waiting] && ![seen containsObject:identifier]) {
      [seen addObject:identifier];
      [identifiers addObject:identifier];
    }
  }
  NSUInteger count = identifiers.count;
  if (count < 2) {
    return identifiers;
  }
  // Sorted through plain arrays: a comparator that looks two keys up in a dictionary for each
  // of the ~16 000 comparisons of 1500 markers costs half a slice.
  double *keys = malloc(count * sizeof(double));
  NSUInteger *indices = malloc(count * sizeof(NSUInteger));
  for (NSUInteger i = 0; i < count; i++) {
    keys[i] = key(identifiers[i]);
    indices[i] = i;
  }
  qsort_b(indices, count, sizeof(NSUInteger), ^int(const void *left, const void *right) {
    NSUInteger a = *(const NSUInteger *)left;
    NSUInteger b = *(const NSUInteger *)right;
    if (keys[a] != keys[b]) {
      return keys[a] < keys[b] ? -1 : 1;
    }
    return a < b ? -1 : (a > b ? 1 : 0);
  });
  NSMutableArray<NSString *> *sorted = [[NSMutableArray alloc] initWithCapacity:count];
  for (NSUInteger i = 0; i < count; i++) {
    [sorted addObject:identifiers[indices[i]]];
  }
  free(keys);
  free(indices);
  return sorted;
}

- (BOOL)isIdentifier:(NSString *)identifier waitingIn:(id)waiting {
  return [waiting isKindOfClass:[NSSet class]] ? [(NSSet *)waiting containsObject:identifier]
                                               : ((NSDictionary *)waiting)[identifier] != nil;
}

- (FGMMarkerOperationKind)takeNextOperationWithMarker:
                              (FGMPlatformMarker *_Nullable __autoreleasing *_Nonnull)marker
                                           identifier:(NSString *_Nullable __autoreleasing *_Nonnull)
                                                          identifier {
  *marker = nil;
  *identifier = nil;
  FGMMarkerOperationKind kind = FGMMarkerOperationKindNone;
  if (_changes.count > 0) {
    NSString *next = [self nextIdentifierIn:_changeOrder cursor:&_changeCursor waiting:_changes];
    *marker = _changes[next];
    *identifier = next;
    [_changes removeObjectForKey:next];
    kind = FGMMarkerOperationKindChange;
  } else if (_removals.count > 0 && (_balance >= 0 || _additions.count == 0)) {
    NSString *next = [self nextIdentifierIn:_removalOrder cursor:&_removalCursor waiting:_removals];
    *identifier = next;
    [_removals removeObject:next];
    _balance -= 1;
    kind = FGMMarkerOperationKindRemove;
  } else if (_additions.count > 0) {
    NSString *next = [self nextIdentifierIn:_additionOrder
                                     cursor:&_additionCursor
                                    waiting:_additions];
    *marker = _additions[next];
    *identifier = next;
    [_additions removeObjectForKey:next];
    _balance += 1;
    kind = FGMMarkerOperationKindAdd;
  }
  [self resetIfEmpty];
  return kind;
}

- (nullable FGMPlatformMarker *)takeNextAdditionPassingTest:
    (BOOL (NS_NOESCAPE ^)(FGMPlatformMarker *marker))test {
  if (_additions.count == 0) {
    return nil;
  }
  NSUInteger cursor = _additionCursor;
  NSString *next = [self nextIdentifierIn:_additionOrder cursor:&cursor waiting:_additions];
  FGMPlatformMarker *marker = _additions[next];
  if (!test(marker)) {
    return nil;
  }
  _additionCursor = cursor;
  [_additions removeObjectForKey:next];
  _balance += 1;
  [self resetIfEmpty];
  return marker;
}

- (FGMMarkerOperationKind)takeOperationForIdentifier:(NSString *)identifier
                                              marker:(FGMPlatformMarker *_Nullable __autoreleasing
                                                          *_Nonnull)marker {
  *marker = nil;
  FGMMarkerOperationKind kind = FGMMarkerOperationKindNone;
  if (_additions[identifier] != nil) {
    *marker = _additions[identifier];
    [_additions removeObjectForKey:identifier];
    _balance += 1;
    kind = FGMMarkerOperationKindAdd;
  } else if (_changes[identifier] != nil) {
    *marker = _changes[identifier];
    [_changes removeObjectForKey:identifier];
    kind = FGMMarkerOperationKindChange;
  }
  [self resetIfEmpty];
  return kind;
}

- (BOOL)isWaitingToRemove:(NSString *)identifier {
  return [_removals containsObject:identifier];
}

/// The first identifier from the cursor on that is still waiting. `waiting` is the dictionary or
/// the set of its kind and is known not to be empty, so there is one.
- (NSString *)nextIdentifierIn:(NSArray<NSString *> *)order
                        cursor:(NSUInteger *)cursor
                       waiting:(id)waiting {
  while (YES) {
    NSString *identifier = order[*cursor];
    *cursor += 1;
    if ([self isIdentifier:identifier waitingIn:waiting]) {
      return identifier;
    }
  }
}

/// An empty queue forgets its order and its balance, so that the arrays do not grow for the life
/// of the map.
- (void)resetIfEmpty {
  if (self.count > 0) {
    return;
  }
  [_additionOrder removeAllObjects];
  [_changeOrder removeAllObjects];
  [_removalOrder removeAllObjects];
  _additionCursor = 0;
  _changeCursor = 0;
  _removalCursor = 0;
  _balance = 0;
}

@end
