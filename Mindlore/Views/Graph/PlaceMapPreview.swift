import MapKit
import SwiftUI

// The entity page's map. A real Map rather than a snapshot: there is one on screen at a time, it
// is worth being able to pan, and the page is not opened and closed the way a card is.
struct PlaceMapPreview: View {
    let coordinate: PlaceCoordinate

    private var position: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            latitudinalMeters: 600,
            longitudinalMeters: 600
        ))
    }

    var body: some View {
        Map(initialPosition: position, interactionModes: [.pan, .zoom]) {
            Marker("", coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(true)
        .accessibilityLabel("Map of this place")
    }
}
