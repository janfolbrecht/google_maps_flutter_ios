// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import Flutter;
@import GoogleMaps;

#import "FGMAssetProvider.h"
#import "FGMCATransactionWrapper.h"
#import "FGMGoogleMapController.h"
#import "FGMMarkerController.h"

NS_ASSUME_NONNULL_BEGIN

/// Implementation of the Pigeon maps API.
///
/// This is a separate object from the maps controller because the Pigeon API registration keeps a
/// strong reference to the implementor, but as the FlutterPlatformView, the lifetime of the
/// FGMGoogleMapController instance is what needs to trigger Pigeon unregistration, so can't be
/// the target of the registration.
@interface FGMMapCallHandler : NSObject <FGMMapsApi>

/// The transaction wrapper to use for camera animations.
@property(nonatomic, strong) id<FGMCATransactionProtocol> transactionWrapper;

/// RedMap fork. Whether a marker batch is applied in slices (FGM_OPT_CHUNKED_BATCH, which this
/// starts from) or in one piece as upstream does. A property so that a test can have both.
@property(nonatomic, assign) BOOL appliesMarkerBatchesInSlices;

@end

/// Implementation of the Pigeon maps inspector API.
///
/// This is a separate object from the maps controller because the Pigeon API registration keeps a
/// strong reference to the implementor, but as the FlutterPlatformView, the lifetime of the
/// FGMGoogleMapController instance is what needs to trigger Pigeon unregistration, so can't be
/// the target of the registration.
@interface FGMMapInspector : NSObject <FGMMapsInspectorApi>

/// Initializes a Pigeon API for inpector with a map controller.
- (instancetype)initWithMapController:(nonnull FGMGoogleMapController *)controller
                            messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                         pigeonSuffix:(NSString *)suffix;

@end

@interface FGMGoogleMapController (Test)

/// Initializes a map controller with a concrete map view.
///
/// @param mapView A map view that will be displayed by the controller
/// @param viewId A unique identifier for the controller.
/// @param creationParameters Parameters for initialising the map view.
/// @param assetProvider The asset provider to use for looking up assets.
/// @param binaryMessenger The binary messenger to use for sending messages to Dart.
- (instancetype)initWithMapView:(GMSMapView *)mapView
                 viewIdentifier:(int64_t)viewId
             creationParameters:(FGMPlatformMapViewCreationParams *)creationParameters
                  assetProvider:(NSObject<FGMAssetProvider> *)assetProvider
                binaryMessenger:(NSObject<FlutterBinaryMessenger> *)binaryMessenger;

// The main Pigeon API implementation.
@property(nonatomic, strong, readonly) FGMMapCallHandler *callHandler;

// The controller of the map's markers.
@property(nonatomic, strong, readonly) FGMMarkersController *markersController;

@end

NS_ASSUME_NONNULL_END
