import SwiftUI

// The head of a card or page: a linked contact's photo for a person, a map for a linked place,
// otherwise the kind's symbol. Neither picture is stored. The photo comes from Contacts and the
// map from a snapshotter every time, so what the phone knows is what shows, and the journal never
// holds a copy of either.
struct EntityAvatar: View {
    @Environment(\.contactDirectory) private var contacts
    @Environment(\.placeDirectory) private var places
    @Environment(\.colorScheme) private var colorScheme
    let kind: EntityKind
    var contactIdentifier: String?
    var place: PlaceCoordinate?
    var size: CGFloat = 44

    @State private var picture: Image?

    var body: some View {
        ZStack {
            if let picture {
                picture
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(kind.color.opacity(0.15))
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(kind.color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
        .task(id: Key(contact: contactIdentifier, place: place, dark: colorScheme == .dark)) { await load() }
    }

    private struct Key: Equatable {
        let contact: String?
        let place: PlaceCoordinate?
        let dark: Bool
    }

    private func load() async {
        picture = nil
        // A contact the app can no longer read, or a place whose snapshot fails, falls back to
        // the symbol without a word: the page is where a broken link is explained.
        if kind == .person, let contactIdentifier {
            guard let data = await contacts.contact(contactIdentifier)?.thumbnail else { return }
            picture = image(data)
        } else if kind == .place, let place {
            let pixels = CGSize(width: size, height: size)
            guard let data = await places.thumbnail(for: place, size: pixels, dark: colorScheme == .dark) else { return }
            picture = image(data)
        }
    }

    private func image(_ data: Data) -> Image? {
        UIImage(data: data).map(Image.init(uiImage:))
    }
}

// Injected the way every other boundary here is, so a preview or a test never reaches the real
// address book or the network, and nothing asks for permission until the user taps a row.
private struct ContactDirectoryKey: EnvironmentKey {
    static let defaultValue: any ContactDirectory = UnavailableContactDirectory()
}

private struct PlaceDirectoryKey: EnvironmentKey {
    static let defaultValue: any PlaceDirectory = UnavailablePlaceDirectory()
}

extension EnvironmentValues {
    var contactDirectory: any ContactDirectory {
        get { self[ContactDirectoryKey.self] }
        set { self[ContactDirectoryKey.self] = newValue }
    }

    var placeDirectory: any PlaceDirectory {
        get { self[PlaceDirectoryKey.self] }
        set { self[PlaceDirectoryKey.self] = newValue }
    }
}
