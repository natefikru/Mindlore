import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Mindlore

// No network and no MapKit: a fake stands in for Apple Maps.
final class FakePlaceDirectory: PlaceDirectory, @unchecked Sendable {
    var results: [PlaceMatch]
    var thumbnailData: Data?
    private(set) var searches: [String] = []

    init(results: [PlaceMatch] = [], thumbnailData: Data? = nil) {
        self.results = results
        self.thumbnailData = thumbnailData
    }

    func search(_ query: String) async -> [PlaceMatch] {
        searches.append(query)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return results
    }

    func thumbnail(for coordinate: PlaceCoordinate, size: CGSize, dark: Bool) async -> Data? {
        thumbnailData
    }
}

@MainActor
struct PlaceLinkTests {
    let harness: GraphHarness
    let editor = GraphEditor(diagnostics: .disabled)

    private let harborCoffee = PlaceCoordinate(latitude: 47.6062, longitude: -122.3321)

    init() throws {
        harness = try GraphHarness()
    }

    private func place(_ name: String = "Harbor Coffee") throws -> Entity {
        let entity = Entity(name: name, key: EntityNormalizer.key(for: name, kind: .place), kind: .place)
        harness.context.insert(entity)
        try harness.context.save()
        return entity
    }

    @Test func linkingStoresTheCoordinateAndIdentifierAndNoName() throws {
        let entity = try place()

        #expect(editor.linkPlace(entity, identifier: "MAPS-1", coordinate: harborCoffee, in: harness.context) == .applied)

        #expect(entity.placeIdentifier == "MAPS-1")
        #expect(entity.placeCoordinate == harborCoffee)
        // The entity already carries the name the user calls it by; Apple's is not stored.
        #expect(entity.name == "Harbor Coffee")
        #expect(entity.bio == nil)
    }

    // Apple documents that a map item identifier can stop resolving, so the coordinate has to
    // stand on its own.
    @Test func aResultWithNoIdentifierStillLinksByCoordinate() throws {
        let entity = try place()

        editor.linkPlace(entity, identifier: nil, coordinate: harborCoffee, in: harness.context)

        #expect(entity.placeIdentifier == nil)
        #expect(entity.placeCoordinate == harborCoffee)
    }

    @Test func unlinkingClearsAllThree() throws {
        let entity = try place()
        editor.linkPlace(entity, identifier: "MAPS-1", coordinate: harborCoffee, in: harness.context)

        #expect(editor.unlinkPlace(entity, in: harness.context) == .applied)
        #expect(entity.placeIdentifier == nil)
        #expect(entity.placeLatitude == nil)
        #expect(entity.placeLongitude == nil)
        #expect(entity.placeCoordinate == nil)
    }

    @Test func onlyAPlaceCanLinkALocation() throws {
        let person = Entity(name: "Sarah", key: "sarah", kind: .person)
        harness.context.insert(person)

        editor.linkPlace(person, identifier: "MAPS-1", coordinate: harborCoffee, in: harness.context)

        #expect(person.placeCoordinate == nil)
    }

    @Test func anImpossibleCoordinateIsRefused() throws {
        let entity = try place()

        editor.linkPlace(entity, identifier: nil, coordinate: PlaceCoordinate(latitude: 500, longitude: 0), in: harness.context)

        #expect(entity.placeCoordinate == nil)
    }

    // Half a coordinate is not a location, whatever is in the store.
    @Test func aHalfWrittenCoordinateReadsAsNone() throws {
        let entity = try place()
        entity.placeLatitude = 47.6

        #expect(entity.placeCoordinate == nil)
    }

    @Test func changingAwayFromPlaceDropsTheLocation() throws {
        let entity = try place()
        editor.linkPlace(entity, identifier: "MAPS-1", coordinate: harborCoffee, in: harness.context)

        #expect(editor.setKind(.organization, on: entity, in: harness.context) == .applied)
        #expect(entity.placeCoordinate == nil)
        #expect(entity.placeIdentifier == nil)
    }

    @Test func theSummaryCarriesThePlaceForTheCard() throws {
        let entity = try place()
        editor.linkPlace(entity, identifier: "MAPS-1", coordinate: harborCoffee, in: harness.context)
        try harness.context.save()
        let graph = GraphServices(diagnostics: .disabled)

        let summary = EntityPeekPresentation.load(entity.id, graph: graph, in: harness.context)

        #expect(summary?.place == harborCoffee)
    }

    @Test func anEmptyQueryNeverSearches() async {
        let directory = FakePlaceDirectory(results: [
            PlaceMatch(identifier: "MAPS-1", name: "Harbor Coffee", locality: "Seattle", coordinate: harborCoffee)
        ])

        #expect(await directory.search("").isEmpty)
        #expect(await directory.search("Harbor").count == 1)
    }

    @Test func coordinateValidityIsChecked() {
        #expect(PlaceCoordinate(latitude: 47.6, longitude: -122.3).isValid)
        #expect(PlaceCoordinate(latitude: -90, longitude: 180).isValid)
        #expect(!PlaceCoordinate(latitude: 91, longitude: 0).isValid)
        #expect(!PlaceCoordinate(latitude: 0, longitude: 181).isValid)
    }
}
