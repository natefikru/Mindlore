import CoreGraphics
import Foundation

// A place's spot on the map. Plain numbers, so nothing here needs MapKit and it crosses actor
// boundaries freely.
nonisolated struct PlaceCoordinate: Sendable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
}

nonisolated struct PlaceMatch: Sendable, Equatable, Identifiable {
    // MKMapItem.Identifier, when the result has one. Apple documents that it can stop resolving,
    // so the coordinate is what the app falls back to and neither is the whole answer alone.
    let identifier: String?
    let name: String
    // Shown in the picker so two places with the same name can be told apart. Never stored.
    let locality: String?
    let coordinate: PlaceCoordinate

    var id: String { identifier ?? "\(coordinate.latitude),\(coordinate.longitude)" }
}

// No method hands back an MKMapItem: it is not Sendable, so the view builds one from the
// identifier and coordinate on the main actor when the user asks for Apple Maps.
nonisolated protocol PlaceDirectory: Sendable {
    @concurrent func search(_ query: String) async -> [PlaceMatch]
    @concurrent func thumbnail(for coordinate: PlaceCoordinate, size: CGSize, dark: Bool) async -> Data?
}

nonisolated struct UnavailablePlaceDirectory: PlaceDirectory {
    @concurrent func search(_ query: String) async -> [PlaceMatch] { [] }
    @concurrent func thumbnail(for coordinate: PlaceCoordinate, size: CGSize, dark: Bool) async -> Data? { nil }
}
