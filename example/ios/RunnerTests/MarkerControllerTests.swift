// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import GoogleMaps
import Testing

@testable import google_maps_flutter_ios

@MainActor struct MarkerControllerTests {

  /// Returns a simple map view for use with marker controllers.
  static func mapView() -> GMSMapView {
    let mapViewOptions = GMSMapViewOptions()
    mapViewOptions.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    mapViewOptions.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)
    return PartiallyMockedMapView(options: mapViewOptions)
  }

  /// Returns a real map view, on which a marker's map can be set and read back.
  static func realMapView() -> GMSMapView {
    let mapViewOptions = GMSMapViewOptions()
    mapViewOptions.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    mapViewOptions.camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 0)
    return GMSMapView(options: mapViewOptions)
  }

  /// Returns a FGMMarkersController instance instantiated with the given map view.
  ///
  /// The mapView should outlive the controller, as the controller keeps a weak reference to it.
  func markersController(
    withMapView mapView: GMSMapView,
    eventDelegate: NSObject & FGMMapEventDelegate
  ) -> FGMMarkersController {
    return FGMMarkersController(
      mapView: mapView,
      eventDelegate: eventDelegate,
      clusterManagersController: nil,
      assetProvider: TestAssetProvider(),
      markerType: .marker
    )
  }

  func placeholderBitmap() -> FGMPlatformBitmap {
    return FGMPlatformBitmap.make(withBitmap: FGMPlatformBitmapDefaultMarker.make(withHue: 0))
  }

  @Test func setsMarkerNumericProperties() throws {
    let mapView = MarkerControllerTests.mapView()
    let eventHandler = TestMapEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)

    let markerIdentifier = "marker"
    let anchorX = 3.14
    let anchorY = 2.718
    let alpha = 0.4
    let rotation = 90.0
    let zIndex = 3
    let latitude = 10.0
    let longitude = 20.0
    controller.add([
      FGMPlatformMarker.make(
        withAlpha: alpha,
        anchor: FGMPlatformPoint.makeWith(x: anchorX, y: anchorY),
        consumeTapEvents: true,
        draggable: true,
        flat: true,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: "info title",
          snippet: "info snippet",
          anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
        ),
        position: FGMPlatformLatLng.make(withLatitude: latitude, longitude: longitude),
        rotation: rotation,
        visible: true,
        zIndex: zIndex,
        markerId: markerIdentifier,
        clusterManagerId: nil,
        collisionBehavior: nil
      )
    ])

    let markerController = try #require(
      controller.markerIdentifierToController[markerIdentifier] as? FGMMarkerController
    )
    let marker = try #require(markerController.marker)

    let delta = 0.0001
    #expect(abs(Double(marker.opacity) - alpha) <= delta)
    #expect(abs(marker.rotation - rotation) <= delta)
    #expect(abs(Double(marker.zIndex) - Double(zIndex)) <= delta)
    #expect(abs(Double(marker.groundAnchor.x) - anchorX) <= delta)
    #expect(abs(Double(marker.groundAnchor.y) - anchorY) <= delta)
    #expect(abs(marker.position.latitude - latitude) <= delta)
    #expect(abs(marker.position.longitude - longitude) <= delta)
  }

  @Test func setsDraggable() throws {
    let mapView = MarkerControllerTests.mapView()
    let eventHandler = TestMapEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)

    let markerIdentifier = "marker"
    controller.add([
      FGMPlatformMarker.make(
        withAlpha: 1.0,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0),
        consumeTapEvents: false,
        draggable: true,
        flat: false,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: "info title",
          snippet: "info snippet",
          anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
        ),
        position: FGMPlatformLatLng.make(withLatitude: 0.0, longitude: 0.0),
        rotation: 0,
        visible: false,
        zIndex: 0,
        markerId: markerIdentifier,
        clusterManagerId: nil,
        collisionBehavior: nil
      )
    ])

    let markerController = try #require(
      controller.markerIdentifierToController[markerIdentifier] as? FGMMarkerController
    )
    let marker = try #require(markerController.marker)

    #expect(marker.isDraggable)
  }

  // Boolean properties are tested individually to ensure they aren't accidentally cross-assigned from
  // another property.
  @Test func setsFlat() throws {
    let mapView = MarkerControllerTests.mapView()
    let eventHandler = TestMapEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)

    let markerIdentifier = "marker"
    controller.add([
      FGMPlatformMarker.make(
        withAlpha: 1.0,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0),
        consumeTapEvents: false,
        draggable: false,
        flat: true,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: "info title",
          snippet: "info snippet",
          anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
        ),
        position: FGMPlatformLatLng.make(withLatitude: 0.0, longitude: 0.0),
        rotation: 0,
        visible: false,
        zIndex: 0,
        markerId: markerIdentifier,
        clusterManagerId: nil,
        collisionBehavior: nil
      )
    ])

    let markerController = try #require(
      controller.markerIdentifierToController[markerIdentifier] as? FGMMarkerController
    )
    let marker = try #require(markerController.marker)

    #expect(marker.isFlat)
  }

  // Boolean properties are tested individually to ensure they aren't accidentally cross-assigned from
  // another property.
  @Test func setsVisible() throws {
    let mapView = MarkerControllerTests.mapView()
    let eventHandler = TestMapEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)

    let markerIdentifier = "marker"
    controller.add([
      FGMPlatformMarker.make(
        withAlpha: 1.0,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0),
        consumeTapEvents: false,
        draggable: false,
        flat: false,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: "info title",
          snippet: "info snippet",
          anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
        ),
        position: FGMPlatformLatLng.make(withLatitude: 0.0, longitude: 0.0),
        rotation: 0,
        visible: true,
        zIndex: 0,
        markerId: markerIdentifier,
        clusterManagerId: nil,
        collisionBehavior: nil
      )
    ])

    let markerController = try #require(
      controller.markerIdentifierToController[markerIdentifier] as? FGMMarkerController
    )
    let marker = try #require(markerController.marker)

    // Visibility is controlled by being set to a map.
    #expect(marker.map != nil)
  }

  @Test func setsMarkerInfoWindowProperties() throws {
    let mapView = MarkerControllerTests.mapView()
    let eventHandler = TestMapEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)

    let markerIdentifier = "marker"
    let title = "info title"
    let snippet = "info snippet"
    let anchorX = 3.14
    let anchorY = 2.718
    controller.add([
      FGMPlatformMarker.make(
        withAlpha: 1.0,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0),
        consumeTapEvents: true,
        draggable: true,
        flat: true,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: title,
          snippet: snippet,
          anchor: FGMPlatformPoint.makeWith(x: anchorX, y: anchorY)
        ),
        position: FGMPlatformLatLng.make(withLatitude: 0, longitude: 0),
        rotation: 0,
        visible: true,
        zIndex: 0,
        markerId: markerIdentifier,
        clusterManagerId: nil,
        collisionBehavior: nil
      )
    ])

    let markerController = try #require(
      controller.markerIdentifierToController[markerIdentifier] as? FGMMarkerController
    )
    let marker = try #require(markerController.marker)

    let delta = 0.0001
    #expect(abs(Double(marker.infoWindowAnchor.x) - anchorX) <= delta)
    #expect(abs(Double(marker.infoWindowAnchor.y) - anchorY) <= delta)
    #expect(marker.title == title)
    #expect(marker.snippet == snippet)
  }

  @Test func updateMarkerSetsVisibilityLast() {
    let marker = PropertyOrderValidatingAdvancedMarker()
    let collisionBehavior = FGMPlatformMarkerCollisionBehaviorBox(
      value: .requiredAndHidesOptional
    )
    FGMMarkerController.update(
      marker,
      from: FGMPlatformMarker.make(
        withAlpha: 1.0,
        anchor: FGMPlatformPoint.makeWith(x: 0, y: 0),
        consumeTapEvents: true,
        draggable: true,
        flat: true,
        icon: placeholderBitmap(),
        infoWindow: FGMPlatformInfoWindow.make(
          withTitle: "info title",
          snippet: "info snippet",
          anchor: FGMPlatformPoint.makeWith(x: 0, y: 0)
        ),
        position: FGMPlatformLatLng.make(withLatitude: 0, longitude: 0),
        rotation: 0,
        visible: true,
        zIndex: 0,
        markerId: "marker",
        clusterManagerId: nil,
        collisionBehavior: collisionBehavior
      ),
      with: MarkerControllerTests.mapView(),
      assetProvider: TestAssetProvider(),
      screenScale: 1,
      usingOpacityForVisibility: false
    )
    #expect(marker.hasSetMap)
  }

  @Test func assetProviderIsRetained() {
    var markerController: FGMMarkersController?
    weak var weakAssetProvider: TestAssetProvider?
    autoreleasepool {
      let assetProvider = TestAssetProvider()
      weakAssetProvider = assetProvider

      markerController = FGMMarkersController(
        mapView: MarkerControllerTests.mapView(),
        eventDelegate: TestMapEventHandler(),
        clusterManagersController: nil,
        assetProvider: assetProvider,
        markerType: .marker
      )
    }
    #expect(markerController != nil)
    #expect(weakAssetProvider != nil)
  }

  // RedMap fork, FGM_OPT_CHUNKED_BATCH: the queue of waiting operations.

  func platformMarker(_ identifier: String, alpha: Double = 1) -> FGMPlatformMarker {
    return FGMPlatformMarker.make(
      withAlpha: alpha,
      anchor: FGMPlatformPoint.makeWith(x: 0.5, y: 1),
      consumeTapEvents: true,
      draggable: false,
      flat: false,
      icon: placeholderBitmap(),
      infoWindow: FGMPlatformInfoWindow.make(
        withTitle: "title",
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

  /// Takes everything out of a queue, as "kind identifier" lines.
  func drain(_ queue: FGMMarkerBatchQueue) -> [String] {
    var taken: [String] = []
    while true {
      var marker: FGMPlatformMarker?
      var identifier: NSString?
      let kind = queue.takeNextOperation(with: &marker, identifier: &identifier)
      switch kind {
      case .change: taken.append("change \(marker!.markerId)")
      case .remove: taken.append("remove \(identifier!)")
      case .add: taken.append("add \(marker!.markerId)")
      default: return taken
      }
    }
  }

  @Test func queueHandsOutChangesFirstThenRemovalsAndAdditionsInTurns() {
    let queue = FGMMarkerBatchQueue()
    let onMap: Set<String> = ["a", "b", "c", "d"]

    queue.mergeBatch(
      byAdding: [platformMarker("x"), platformMarker("y"), platformMarker("z")],
      changing: [platformMarker("a")],
      removing: ["b", "c"],
      existsOnMap: { onMap.contains($0) })

    #expect(queue.count == 6)
    #expect(drain(queue) == ["change a", "remove b", "add x", "remove c", "add y", "add z"])
    #expect(queue.count == 0)
  }

  @Test func queueDropsAnAdditionThatALaterBatchRemoves() {
    let queue = FGMMarkerBatchQueue()

    queue.mergeBatch(
      byAdding: [platformMarker("x"), platformMarker("y")], changing: [], removing: [],
      existsOnMap: { _ in false })
    queue.mergeBatch(byAdding: [], changing: [], removing: ["x"], existsOnMap: { _ in false })

    #expect(drain(queue) == ["add y"])
  }

  @Test func queueTurnsARemovalThatComesBackIntoAChange() {
    let queue = FGMMarkerBatchQueue()

    queue.mergeBatch(byAdding: [], changing: [], removing: ["a", "b"], existsOnMap: { _ in true })
    #expect(queue.isWaiting(toRemove: "a"))
    queue.mergeBatch(
      byAdding: [platformMarker("a", alpha: 0.5)], changing: [], removing: [],
      existsOnMap: { _ in true })

    #expect(!queue.isWaiting(toRemove: "a"))
    var marker: FGMPlatformMarker?
    var identifier: NSString?
    #expect(queue.takeNextOperation(with: &marker, identifier: &identifier) == .change)
    #expect(marker?.markerId == "a")
    #expect(marker?.alpha == 0.5)
    #expect(drain(queue) == ["remove b"])
  }

  @Test func queueChangeOfAWaitingAdditionReplacesTheMarkerToAdd() {
    let queue = FGMMarkerBatchQueue()

    queue.mergeBatch(
      byAdding: [platformMarker("x")], changing: [], removing: [], existsOnMap: { _ in false })
    queue.mergeBatch(
      byAdding: [], changing: [platformMarker("x", alpha: 0.5)], removing: [],
      existsOnMap: { _ in false })

    var marker: FGMPlatformMarker?
    var identifier: NSString?
    #expect(queue.takeNextOperation(with: &marker, identifier: &identifier) == .add)
    #expect(marker?.alpha == 0.5)
    #expect(queue.count == 0)
  }

  @Test func queueIgnoresWhatUpstreamIgnores() {
    let queue = FGMMarkerBatchQueue()

    // A change and a removal of a marker that is neither on the map nor waiting.
    queue.mergeBatch(
      byAdding: [], changing: [platformMarker("gone")], removing: ["gone"],
      existsOnMap: { _ in false })
    #expect(queue.count == 0)

    // A change of a marker that is waiting to be removed: upstream removed it before.
    queue.mergeBatch(byAdding: [], changing: [], removing: ["a"], existsOnMap: { _ in true })
    queue.mergeBatch(
      byAdding: [], changing: [platformMarker("a")], removing: [], existsOnMap: { _ in true })
    #expect(drain(queue) == ["remove a"])
  }

  @Test func queueKeepsAMarkerAddedRemovedAndAddedAgainOnce() {
    let queue = FGMMarkerBatchQueue()

    queue.mergeBatch(
      byAdding: [platformMarker("x")], changing: [], removing: [], existsOnMap: { _ in false })
    queue.mergeBatch(byAdding: [], changing: [], removing: ["x"], existsOnMap: { _ in false })
    queue.mergeBatch(
      byAdding: [platformMarker("y"), platformMarker("x")], changing: [], removing: [],
      existsOnMap: { _ in false })

    #expect(drain(queue) == ["add y", "add x"])
  }

  // RedMap fork, FGM_OPT_CHUNKED_BATCH: the slices.

  /// Keeps the slices a markers controller asks for, so that a test runs them one by one.
  class SliceRecorder {
    var slices: [() -> Void] = []

    func attach(to controller: FGMMarkersController) {
      // Every slice is one operation, and no batch is small enough to be applied whole.
      controller.sliceBudget = 0
      controller.unsplitOperationLimit = 0
      controller.sliceScheduler = { [unowned self] slice in self.slices.append(slice!) }
    }

    /// Runs the waiting slice; false when there is none.
    func runNext() -> Bool {
      if slices.isEmpty { return false }
      slices.removeFirst()()
      return true
    }

    func runAll() {
      while runNext() {}
    }
  }

  func identifiers(of controller: FGMMarkersController) -> Set<String> {
    return Set(controller.markerIdentifierToController.allKeys.map { $0 as! String })
  }

  func gmsMarker(_ identifier: String, of controller: FGMMarkersController) -> GMSMarker? {
    return (controller.markerIdentifierToController[identifier] as? FGMMarkerController)?.marker
  }

  @Test func smallBatchIsAppliedWithinTheCall() {
    let mapView = MarkerControllerTests.realMapView()
    let controller = markersController(withMapView: mapView, eventDelegate: TestMapEventHandler())
    var scheduled = 0
    controller.sliceScheduler = { _ in scheduled += 1 }

    controller.updateMarkersInSlices(
      byAdding: [platformMarker("a"), platformMarker("b"), platformMarker("c")],
      changing: [], removing: [])

    #expect(identifiers(of: controller) == ["a", "b", "c"])
    #expect(controller.waitingOperationCount() == 0)
    #expect(scheduled == 0)
  }

  @Test func largeBatchIsAppliedSliceBySlice() {
    let mapView = MarkerControllerTests.realMapView()
    let controller = markersController(withMapView: mapView, eventDelegate: TestMapEventHandler())
    let recorder = SliceRecorder()
    recorder.attach(to: controller)

    controller.updateMarkersInSlices(
      byAdding: ["a", "b", "c", "d"].map { platformMarker($0) }, changing: [], removing: [])

    // The first slice ran within the call; the next one is asked for, once.
    #expect(identifiers(of: controller) == ["a"])
    #expect(controller.waitingOperationCount() == 3)
    #expect(recorder.slices.count == 1)

    #expect(recorder.runNext())
    #expect(identifiers(of: controller) == ["a", "b"])
    #expect(recorder.slices.count == 1)

    recorder.runAll()
    #expect(identifiers(of: controller) == ["a", "b", "c", "d"])
    #expect(controller.waitingOperationCount() == 0)
    for identifier in ["a", "b", "c", "d"] {
      #expect(gmsMarker(identifier, of: controller)?.map === mapView)
    }
  }

  @Test func batchThatComesBetweenSlicesIsMergedWithTheRest() {
    let mapView = MarkerControllerTests.realMapView()
    let controller = markersController(withMapView: mapView, eventDelegate: TestMapEventHandler())
    let recorder = SliceRecorder()
    recorder.attach(to: controller)

    controller.updateMarkersInSlices(
      byAdding: ["a", "b", "c", "d"].map { platformMarker($0) }, changing: [], removing: [])
    #expect(identifiers(of: controller) == ["a"])
    let markerA = gmsMarker("a", of: controller)

    // The Dart side now holds a, b, c, d and sends the step to c, d, e: "a" is on the map, "b"
    // is still waiting.
    controller.updateMarkersInSlices(
      byAdding: [platformMarker("e")], changing: [], removing: ["a", "b"])
    recorder.runAll()

    #expect(identifiers(of: controller) == ["c", "d", "e"])
    #expect(controller.waitingOperationCount() == 0)
    #expect(markerA?.map == nil)
    // One slice was asked for at a time, however many batches came.
    #expect(recorder.slices.isEmpty)
  }

  @Test func markerThatGoesAndComesBackBetweenSlicesStaysTheSameMarker() {
    let mapView = MarkerControllerTests.realMapView()
    let controller = markersController(withMapView: mapView, eventDelegate: TestMapEventHandler())
    controller.updateMarkersInSlices(
      byAdding: ["a", "b", "c"].map { platformMarker($0) }, changing: [], removing: [])
    let markerC = gmsMarker("c", of: controller)
    let recorder = SliceRecorder()
    recorder.attach(to: controller)

    controller.updateMarkersInSlices(byAdding: [], changing: [], removing: ["a", "b", "c"])
    #expect(identifiers(of: controller) == ["b", "c"])
    controller.updateMarkersInSlices(
      byAdding: [platformMarker("c", alpha: 0.5)], changing: [], removing: [])
    recorder.runAll()

    #expect(identifiers(of: controller) == ["c"])
    #expect(gmsMarker("c", of: controller) === markerC)
    #expect(markerC?.map === mapView)
    #expect(markerC?.opacity == 0.5)
  }

  /// Counts the taps that reach the Dart side.
  class TapCountingEventHandler: TestMapEventHandler {
    var tapped: [String] = []
    override func didTapMarker(withIdentifier markerId: String) {
      tapped.append(markerId)
    }
  }

  @Test func tapOnAMarkerWaitingToBeRemovedIsNotSent() {
    let mapView = MarkerControllerTests.realMapView()
    let eventHandler = TapCountingEventHandler()
    let controller = markersController(withMapView: mapView, eventDelegate: eventHandler)
    controller.updateMarkersInSlices(
      byAdding: ["a", "b", "c"].map { platformMarker($0) }, changing: [], removing: [])
    let recorder = SliceRecorder()
    recorder.attach(to: controller)

    controller.updateMarkersInSlices(byAdding: [], changing: [], removing: ["a", "b"])
    // "a" went with the first slice, "b" is on the map until the next one.
    #expect(identifiers(of: controller) == ["b", "c"])

    #expect(controller.didTapMarker(withIdentifier: "b"))
    #expect(eventHandler.tapped.isEmpty)
    #expect(controller.didTapMarker(withIdentifier: "c"))
    #expect(eventHandler.tapped == ["c"])

    var error: FlutterError?
    controller.showMarkerInfoWindow(withIdentifier: "b", error: &error)
    #expect(error?.code == "Invalid markerId")
  }

  @Test func infoWindowOfAWaitingMarkerPutsItOnTheMapFirst() {
    let mapView = MarkerControllerTests.realMapView()
    let controller = markersController(withMapView: mapView, eventDelegate: TestMapEventHandler())
    let recorder = SliceRecorder()
    recorder.attach(to: controller)

    controller.updateMarkersInSlices(
      byAdding: ["a", "b", "c"].map { platformMarker($0) }, changing: [], removing: [])
    #expect(identifiers(of: controller) == ["a"])

    var error: FlutterError?
    controller.showMarkerInfoWindow(withIdentifier: "c", error: &error)

    #expect(error == nil)
    #expect(identifiers(of: controller) == ["a", "c"])
    #expect(mapView.selectedMarker === gmsMarker("c", of: controller))

    recorder.runAll()
    #expect(identifiers(of: controller) == ["a", "b", "c"])
    #expect(controller.waitingOperationCount() == 0)
  }

  /// Counts how often clustering is invoked.
  class CountingClusterManagersController: FGMClusterManagersController {
    var invocations = 0
    override func invokeClusteringForEachClusterManager() {
      invocations += 1
      super.invokeClusteringForEachClusterManager()
    }
  }

  @Test func clusteringIsInvokedOnceAfterTheLastSlice() {
    let mapView = MarkerControllerTests.realMapView()
    let eventHandler = TestMapEventHandler()
    let clusterManagers = CountingClusterManagersController(
      mapView: mapView, eventDelegate: eventHandler)
    let controller = FGMMarkersController(
      mapView: mapView,
      eventDelegate: eventHandler,
      clusterManagersController: clusterManagers,
      assetProvider: TestAssetProvider(),
      markerType: .marker
    )

    // A batch applied within the call, and an empty one: once each, as upstream.
    controller.updateMarkersInSlices(byAdding: [platformMarker("a")], changing: [], removing: [])
    #expect(clusterManagers.invocations == 1)
    controller.updateMarkersInSlices(byAdding: [], changing: [], removing: [])
    #expect(clusterManagers.invocations == 2)

    let recorder = SliceRecorder()
    recorder.attach(to: controller)
    controller.updateMarkersInSlices(
      byAdding: ["b", "c", "d"].map { platformMarker($0) }, changing: [], removing: [])
    #expect(recorder.runNext())
    // An empty batch between two slices does not end the batch in progress.
    controller.updateMarkersInSlices(byAdding: [], changing: [], removing: [])
    #expect(clusterManagers.invocations == 2)

    recorder.runAll()
    #expect(identifiers(of: controller) == ["a", "b", "c", "d"])
    #expect(clusterManagers.invocations == 3)
  }

  @Test func sliceScheduledForAControllerThatIsGoneDoesNothing() {
    let mapView = MarkerControllerTests.realMapView()
    let recorder = SliceRecorder()
    do {
      let controller = markersController(
        withMapView: mapView, eventDelegate: TestMapEventHandler())
      recorder.attach(to: controller)
      controller.updateMarkersInSlices(
        byAdding: ["a", "b"].map { platformMarker($0) }, changing: [], removing: [])
      #expect(recorder.slices.count == 1)
    }

    // The map went away with slices still waiting; the block holds the controller weakly.
    recorder.runAll()
  }

}

/// A GMSAdvancedMarker that ensures that property updates are made before the map is set.
class PropertyOrderValidatingAdvancedMarker: GMSAdvancedMarker {
  var hasSetMap = false

  override var position: CLLocationCoordinate2D {
    get { super.position }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.position = newValue
    }
  }

  override var snippet: String? {
    get { super.snippet }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.snippet = newValue
    }
  }

  override var icon: UIImage? {
    get { super.icon }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.icon = newValue
    }
  }

  override var iconView: UIView? {
    get { super.iconView }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.iconView = newValue
    }
  }

  override var tracksViewChanges: Bool {
    get { super.tracksViewChanges }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.tracksViewChanges = newValue
    }
  }

  override var tracksInfoWindowChanges: Bool {
    get { super.tracksInfoWindowChanges }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.tracksInfoWindowChanges = newValue
    }
  }

  override var groundAnchor: CGPoint {
    get { super.groundAnchor }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.groundAnchor = newValue
    }
  }

  override var infoWindowAnchor: CGPoint {
    get { super.infoWindowAnchor }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.infoWindowAnchor = newValue
    }
  }

  override var appearAnimation: GMSMarkerAnimation {
    get { super.appearAnimation }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.appearAnimation = newValue
    }
  }

  override var isDraggable: Bool {
    get { super.isDraggable }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.isDraggable = newValue
    }
  }

  override var isFlat: Bool {
    get { super.isFlat }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.isFlat = newValue
    }
  }

  override var rotation: CLLocationDegrees {
    get { super.rotation }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.rotation = newValue
    }
  }

  override var opacity: Float {
    get { super.opacity }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.opacity = newValue
    }
  }

  override var panoramaView: GMSPanoramaView? {
    get { super.panoramaView }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.panoramaView = newValue
    }
  }

  override var title: String? {
    get { super.title }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.title = newValue
    }
  }

  override var isTappable: Bool {
    get { super.isTappable }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.isTappable = newValue
    }
  }

  override var zIndex: Int32 {
    get { super.zIndex }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.zIndex = newValue
    }
  }

  override var userData: Any? {
    get { super.userData }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.userData = newValue
    }
  }

  override var collisionBehavior: GMSCollisionBehavior {
    get { super.collisionBehavior }
    set {
      #expect(!hasSetMap, "Property set after map was set.")
      super.collisionBehavior = newValue
    }
  }

  override var map: GMSMapView? {
    get { super.map }
    set {
      // Don't actually set the map, since that requires more test setup.
      if newValue != nil {
        hasSetMap = true
      }
    }
  }
}
