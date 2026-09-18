import MapKit
import UIKit

// Real places from Apple Maps. No region bias and no location permission: the app never asks
// where the user is, so a search is the entity's name and nothing else.
//
// Searching does send that name to Apple, and drawing a preview sends the coordinate. Nothing is
// stored and nothing is logged, but the picker says so rather than implying nothing leaves the
// phone.
nonisolated final class MKPlaceDirectory: PlaceDirectory {
    private let snapshots = SnapshotCache()
    private static let maxResults = 25

    func search(_ query: String) async -> [PlaceMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(Self.maxResults).map(Self.match)
    }

    static func match(_ item: MKMapItem) -> PlaceMatch {
        let placemark = item.placemark
        return PlaceMatch(
            identifier: item.identifier?.rawValue,
            name: item.name ?? placemark.name ?? "Unnamed place",
            locality: [placemark.locality, placemark.administrativeArea].compactMap { $0 }.first,
            coordinate: PlaceCoordinate(
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            )
        )
    }

    // A still image, not a live Map: the slot is 44 points square on a card that opens and closes
    // constantly, and a map view there costs far more than a picture of one.
    func thumbnail(for coordinate: PlaceCoordinate, size: CGSize, dark: Bool) async -> Data? {
        guard coordinate.isValid, size.width > 0, size.height > 0 else { return nil }
        let key = SnapshotCache.Key(coordinate: coordinate, size: size, dark: dark)
        if let cached = await snapshots.image(for: key) { return cached }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let data = snapshot.image.pngData() else { return nil }
        await snapshots.store(data, for: key)
        return data
    }

    // What Apple Maps should open. Built on the main actor by the caller, since MKMapItem is not
    // Sendable. The identifier gives the real place with its hours and reviews; Apple documents
    // that it can stop resolving, so the coordinate is always the fallback.
    @MainActor
    static func mapItem(identifier: String?, coordinate: PlaceCoordinate, name: String) async -> MKMapItem {
        if let identifier, let mapItemIdentifier = MKMapItem.Identifier(rawValue: identifier),
           let found = try? await MKMapItemRequest(mapItemIdentifier: mapItemIdentifier).mapItem {
            return found
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        return item
    }
}

private actor SnapshotCache {
    struct Key: Hashable {
        let coordinate: PlaceCoordinate
        let size: CGSize
        let dark: Bool
    }

    private var byKey: [Key: Data] = [:]
    private var order: [Key] = []
    private let limit = 50

    func image(for key: Key) -> Data? { byKey[key] }

    func store(_ data: Data, for key: Key) {
        if byKey[key] == nil { order.append(key) }
        byKey[key] = data
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            byKey[oldest] = nil
        }
    }
}
