// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import GoogleMaps
import Testing

@testable import google_maps_flutter_ios

class MockCATransaction: NSObject, FGMCATransactionProtocol {
  var beginCalled = false
  var commitCalled = false
  var animationDuration: CFTimeInterval = 0.0

  func begin() {
    beginCalled = true
  }

  func commit() {
    commitCalled = true
  }

  func setAnimationDuration(_ duration: CFTimeInterval) {
    animationDuration = duration
  }
}

// No-op implementation of FlutterBinaryMessenger.
class StubBinaryMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply reply: FlutterBinaryReply?) {}
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    return 0
  }
}

class StubPluginRegistrar: NSObject, FlutterPluginRegistrar {
  var viewController: UIViewController? { nil }
  func publish(_ value: NSObject) {}
  func addMethodCallDelegate(_ delegate: any FlutterPlugin, channel: FlutterMethodChannel) {}
  func addApplicationDelegate(_ delegate: any FlutterPlugin) {}
  func addSceneDelegate(_ delegate: any FlutterSceneLifeCycleDelegate) {}
  func lookupKey(forAsset asset: String) -> String { "" }
  func lookupKey(forAsset asset: String, fromPackage package: String) -> String { "" }
  func valuePublished(byPlugin pluginKey: String) -> NSObject? { nil }
  func messenger() -> any FlutterBinaryMessenger { StubBinaryMessenger() }
  func textures() -> any FlutterTextureRegistry { fatalError() }
  func register(_ factory: any FlutterPlatformViewFactory, withId factoryId: String) {}
  func register(
    _ factory: any FlutterPlatformViewFactory, withId factoryId: String,
    gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy
  ) {}
}

/// A map view that records every value its `accessibilityElementsHidden` is set to.
class AccessibilityRecordingMapView: GMSMapView {
  var hiddenValues: [Bool] = []

  override var accessibilityElementsHidden: Bool {
    get { super.accessibilityElementsHidden }
    set {
      hiddenValues.append(newValue)
      super.accessibilityElementsHidden = newValue
    }
  }
}

@MainActor struct GoogleMapsTests {

  @Test func plugin() {
    // Verify that creating an actual plugin instance succeeds.
    let _ = FGMGoogleMapsPlugin()
  }

  @Test func frameObserver() {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let options = GMSMapViewOptions()
    options.frame = frame
    options.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)
    let mapView = PartiallyMockedMapView(options: options)
    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: emptyCreationParameters(),
      assetProvider: TestAssetProvider(),
      binaryMessenger: StubBinaryMessenger()
    )

    for _ in 0..<10 {
      _ = controller.view()
    }
    #expect(mapView.frameObserverCount == 1)

    mapView.frame = frame
    #expect(mapView.frameObserverCount == 0)
  }

  @Test func mapsServiceSync() {
    // The API requires a registrar, but this test doesn't actually use it, so just pass in a
    // dummy object rather than set up a full mock.
    let registrar = StubPluginRegistrar()
    let factory1 = FGMGoogleMapFactory(registrar: registrar)
    #expect(factory1.sharedMapServices != nil)
    let factory2 = FGMGoogleMapFactory(registrar: registrar)
    // Test pointer equality, should be same retained singleton +[GMSServices sharedServices] object.
    // Retaining the opaque object should be enough to avoid multiple internal initializations,
    // but don't test the internals of the GoogleMaps API. Assume that it does what is documented.
    // https://developers.google.com/maps/documentation/ios-sdk/reference/interface_g_m_s_services#a436e03c32b1c0be74e072310a7158831
    #expect(factory1.sharedMapServices as AnyObject === factory2.sharedMapServices as AnyObject)
  }

  @Test func handleResultTileDownsamplesWideGamutImages() throws {
    let controller = FGMTileProviderController()

    let bundle = Bundle(for: MockCATransaction.self)
    let imagePath = try #require(
      bundle.path(forResource: "widegamut", ofType: "png", inDirectory: "assets"))
    let wideGamutImage = try #require(UIImage(contentsOfFile: imagePath))

    let downsampledImage = try #require(controller.handleResultTile(wideGamutImage))

    let imageRef = try #require(downsampledImage.cgImage)
    let bitsPerComponent = imageRef.bitsPerComponent

    // non wide gamut images use 8 bit format
    #expect(bitsPerComponent == 8)
    #expect(imageRef.alphaInfo == .premultipliedLast)
  }

  @Test func animateCameraWithUpdate() throws {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let mapViewOptions = GMSMapViewOptions()
    mapViewOptions.frame = frame

    // Init camera with zero zoom.
    mapViewOptions.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)

    let mapView = PartiallyMockedMapView(options: mapViewOptions)

    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: emptyCreationParameters(),
      assetProvider: TestAssetProvider(),
      binaryMessenger: StubBinaryMessenger()
    )

    let mockTransactionWrapper = MockCATransaction()
    controller.callHandler.transactionWrapper = mockTransactionWrapper

    let zoomTo = FGMPlatformCameraUpdateZoomTo.make(withZoom: 10.0)
    let cameraUpdate = FGMPlatformCameraUpdate.make(withCameraUpdate: zoomTo)
    var error: FlutterError? = nil

    controller.callHandler.animateCamera(with: cameraUpdate, duration: nil, error: &error)
    #expect(error == nil)
    #expect(mapView.didAnimateCamera)
    #expect(!mockTransactionWrapper.beginCalled)
    #expect(!mockTransactionWrapper.commitCalled)
  }

  @Test func animateCameraWithUpdateAndDuration() throws {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let mapViewOptions = GMSMapViewOptions()
    mapViewOptions.frame = frame

    // Init camera with zero zoom.
    mapViewOptions.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)

    let mapView = PartiallyMockedMapView(options: mapViewOptions)

    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: emptyCreationParameters(),
      assetProvider: TestAssetProvider(),
      binaryMessenger: StubBinaryMessenger()
    )

    let mockTransactionWrapper = MockCATransaction()
    controller.callHandler.transactionWrapper = mockTransactionWrapper

    let zoomTo = FGMPlatformCameraUpdateZoomTo.make(withZoom: 10.0)
    let cameraUpdate = FGMPlatformCameraUpdate.make(withCameraUpdate: zoomTo)
    var error: FlutterError? = nil

    let durationMilliseconds: NSNumber = 100
    controller.callHandler.animateCamera(
      with: cameraUpdate,
      duration: durationMilliseconds,
      error: &error
    )
    #expect(error == nil)
    #expect(mapView.didAnimateCamera)
    #expect(mockTransactionWrapper.beginCalled)
    #expect(mockTransactionWrapper.commitCalled)
    #expect(mockTransactionWrapper.animationDuration == durationMilliseconds.doubleValue / 1000)
  }

  @Test func inspectorAPICameraPosition() throws {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let mapViewOptions = GMSMapViewOptions()
    mapViewOptions.frame = frame

    // Init camera with specific position.
    let initialCameraPosition = GMSCameraPosition(latitude: 37.7749, longitude: -122.4194, zoom: 10)
    mapViewOptions.camera = initialCameraPosition

    let mapView = PartiallyMockedMapView(options: mapViewOptions)

    let binaryMessenger = StubBinaryMessenger()
    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: emptyCreationParameters(),
      assetProvider: TestAssetProvider(),
      binaryMessenger: binaryMessenger
    )

    let inspector = FGMMapInspector(
      mapController: controller,
      messenger: binaryMessenger,
      pigeonSuffix: "0"
    )

    var error: FlutterError? = nil
    let cameraPosition = try #require(inspector.cameraPosition(&error))
    #expect(error == nil)

    #expect(cameraPosition.target.latitude == initialCameraPosition.target.latitude)
    #expect(cameraPosition.target.longitude == initialCameraPosition.target.longitude)
    #expect(Double(cameraPosition.zoom) == Double(initialCameraPosition.zoom))
  }

  // RedMap fork, FGM_OPT_AX_BATCH.

  private func accessibilityRecordingController() -> (
    FGMGoogleMapController, AccessibilityRecordingMapView
  ) {
    let options = GMSMapViewOptions()
    options.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    options.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)
    let mapView = AccessibilityRecordingMapView(options: options)
    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: emptyCreationParameters(),
      assetProvider: TestAssetProvider(),
      binaryMessenger: StubBinaryMessenger()
    )
    // The map view hides the elements when it is made and the controller enables them.
    #expect(mapView.hiddenValues == [true, false])
    mapView.hiddenValues = []
    return (controller, mapView)
  }

  private func marker(_ identifier: String) -> FGMPlatformMarker {
    return FGMPlatformMarker.make(
      withAlpha: 1,
      anchor: FGMPlatformPoint.makeWith(x: 0.5, y: 1),
      consumeTapEvents: true,
      draggable: false,
      flat: false,
      icon: FGMPlatformBitmap.make(withBitmap: FGMPlatformBitmapDefaultMarker.make(withHue: 0)),
      infoWindow: FGMPlatformInfoWindow.make(
        withTitle: nil,
        snippet: nil,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
      ),
      position: FGMPlatformLatLng.make(withLatitude: 0, longitude: 0),
      rotation: 0,
      visible: true,
      zIndex: 0,
      markerId: identifier,
      clusterManagerId: nil,
      collisionBehavior: nil
    )
  }

  @Test func markerBatchHidesAccessibilityElementsAndPutsThemBack() throws {
    let (controller, mapView) = accessibilityRecordingController()

    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(
      byAdding: [marker("a"), marker("b")], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues == [true, false])
    #expect(!mapView.accessibilityElementsHidden)

    controller.callHandler.updateMarkers(
      byAdding: [], changing: [marker("a")], removing: ["b"], error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues == [true, false, true, false])
    #expect(!mapView.accessibilityElementsHidden)
  }

  @Test func emptyMarkerBatchLeavesAccessibilityElementsAlone() {
    let (controller, mapView) = accessibilityRecordingController()

    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(byAdding: [], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues.isEmpty)
    #expect(!mapView.accessibilityElementsHidden)
  }

  @Test func markerBatchLeavesHiddenAccessibilityElementsHidden() {
    let (controller, mapView) = accessibilityRecordingController()
    mapView.accessibilityElementsHidden = true
    mapView.hiddenValues = []

    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(
      byAdding: [marker("a")], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues.isEmpty)
    #expect(mapView.accessibilityElementsHidden)
  }

  // RedMap fork, FGM_OPT_CHUNKED_BATCH, through the Pigeon call.

  @Test func markerBatchInSlicesHidesAccessibilityElementsUntilTheLastSlice() {
    let (controller, mapView) = accessibilityRecordingController()
    #expect(controller.callHandler.appliesMarkerBatchesInSlices)
    var slices: [() -> Void] = []
    controller.markersController.sliceBudget = 0
    controller.markersController.unsplitOperationLimit = 0
    controller.markersController.sliceScheduler = { slices.append($0!) }

    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(
      byAdding: [marker("a"), marker("b"), marker("c")], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(controller.markersController.markerCount() == 1)
    #expect(mapView.hiddenValues == [true])

    while !slices.isEmpty {
      slices.removeFirst()()
    }

    #expect(controller.markersController.markerCount() == 3)
    #expect(mapView.hiddenValues == [true, false])
    #expect(!mapView.accessibilityElementsHidden)
  }

  @Test func markerBatchIsAppliedInOnePieceWhenSlicesAreSwitchedOff() {
    let (controller, mapView) = accessibilityRecordingController()
    var scheduled = 0
    controller.markersController.sliceBudget = 0
    controller.markersController.unsplitOperationLimit = 0
    controller.markersController.sliceScheduler = { _ in scheduled += 1 }
    // What FGM_OPT_CHUNKED_BATCH=0 does to every map of the process.
    controller.callHandler.appliesMarkerBatchesInSlices = false

    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(
      byAdding: [marker("a"), marker("b"), marker("c")], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(controller.markersController.markerCount() == 3)
    #expect(controller.markersController.waitingOperationCount() == 0)
    #expect(scheduled == 0)
    #expect(mapView.hiddenValues == [true, false])

    controller.callHandler.updateMarkers(
      byAdding: [], changing: [marker("a")], removing: ["b", "c"], error: &error)

    #expect(controller.markersController.markerCount() == 1)
    #expect(scheduled == 0)
  }

  // RedMap fork: accessibility elements hidden through the map configuration.

  private func accessibilityRecordingController(
    creationParameters: FGMPlatformMapViewCreationParams
  ) -> (FGMGoogleMapController, AccessibilityRecordingMapView) {
    let options = GMSMapViewOptions()
    options.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    options.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)
    let mapView = AccessibilityRecordingMapView(options: options)
    let controller = FGMGoogleMapController(
      mapView: mapView,
      viewIdentifier: 0,
      creationParameters: creationParameters,
      assetProvider: TestAssetProvider(),
      binaryMessenger: StubBinaryMessenger()
    )
    return (controller, mapView)
  }

  @Test func creationConfigurationHidesAccessibilityElements() {
    let (controller, mapView) = accessibilityRecordingController(
      creationParameters: emptyCreationParameters(accessibilityElementsHidden: true))

    #expect(mapView.accessibilityElementsHidden)

    // The marker batch sees the elements hidden and leaves them alone.
    mapView.hiddenValues = []
    var error: FlutterError? = nil
    controller.callHandler.updateMarkers(
      byAdding: [marker("a")], changing: [], removing: [], error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues.isEmpty)
    #expect(mapView.accessibilityElementsHidden)
  }

  @Test func creationConfigurationWithoutValueLeavesAccessibilityElementsEnabled() {
    let (_, mapView) = accessibilityRecordingController(
      creationParameters: emptyCreationParameters(accessibilityElementsHidden: nil))

    #expect(!mapView.accessibilityElementsHidden)
  }

  @Test func configurationUpdateWithoutValueLeavesHiddenAccessibilityElementsHidden() {
    let (controller, mapView) = accessibilityRecordingController(
      creationParameters: emptyCreationParameters(accessibilityElementsHidden: true))
    mapView.hiddenValues = []

    var error: FlutterError? = nil
    controller.callHandler.update(
      with: emptyMapConfiguration(accessibilityElementsHidden: nil), error: &error)

    #expect(error == nil)
    #expect(mapView.hiddenValues.isEmpty)
    #expect(mapView.accessibilityElementsHidden)
  }

  @Test func configurationUpdateCanShowAccessibilityElementsAgain() {
    let (controller, mapView) = accessibilityRecordingController(
      creationParameters: emptyCreationParameters(accessibilityElementsHidden: true))

    var error: FlutterError? = nil
    controller.callHandler.update(
      with: emptyMapConfiguration(accessibilityElementsHidden: false), error: &error)

    #expect(error == nil)
    #expect(!mapView.accessibilityElementsHidden)
  }

  /// Creates an empty creation parameters object for tests where the values don't matter, just that
  /// there's a valid object to pass in.
  private func emptyCreationParameters(
    accessibilityElementsHidden: NSNumber? = nil
  ) -> FGMPlatformMapViewCreationParams {
    return FGMPlatformMapViewCreationParams.make(
      withInitialCameraPosition: FGMPlatformCameraPosition.make(
        withBearing: 0.0,
        target: FGMPlatformLatLng.make(withLatitude: 0.0, longitude: 0.0),
        tilt: 0.0,
        zoom: 0.0
      ),
      mapConfiguration: emptyMapConfiguration(
        accessibilityElementsHidden: accessibilityElementsHidden),
      initialCircles: [],
      initialMarkers: [],
      initialPolygons: [],
      initialPolylines: [],
      initialHeatmaps: [],
      initialTileOverlays: [],
      initialClusterManagers: [],
      initialGroundOverlays: []
    )
  }

  /// Creates a map configuration that changes nothing but, optionally, the accessibility elements.
  private func emptyMapConfiguration(
    accessibilityElementsHidden: NSNumber? = nil
  ) -> FGMPlatformMapConfiguration {
    return FGMPlatformMapConfiguration.make(
      withCompassEnabled: nil,
      cameraTargetBounds: nil,
      mapType: nil,
      minMaxZoomPreference: nil,
      rotateGesturesEnabled: nil,
      scrollGesturesEnabled: nil,
      tiltGesturesEnabled: nil,
      trackCameraPosition: nil,
      zoomGesturesEnabled: nil,
      myLocationEnabled: nil,
      myLocationButtonEnabled: nil,
      padding: nil,
      indoorViewEnabled: nil,
      trafficEnabled: nil,
      buildingsEnabled: nil,
      markerType: .marker,
      mapId: nil,
      style: nil,
      accessibilityElementsHidden: accessibilityElementsHidden
    )
  }
}
