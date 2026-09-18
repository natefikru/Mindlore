import SwiftUI

// The head of a card or page: a linked contact's photo for a person, otherwise the kind's symbol.
// The photo is fetched every time from Contacts rather than stored, so a photo changed on the
// phone is right here too, and the journal never holds a copy of the address book.
struct EntityAvatar: View {
    @Environment(\.contactDirectory) private var contacts
    let kind: EntityKind
    let contactIdentifier: String?
    var size: CGFloat = 44

    @State private var photo: Image?

    var body: some View {
        ZStack {
            if let photo {
                photo
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
        .task(id: contactIdentifier) { await load() }
    }

    private func load() async {
        photo = nil
        // A contact the app can no longer read falls back to the symbol without a word: the page
        // is where an unreadable link is explained and offered an unlink.
        guard let contactIdentifier, kind == .person,
              let data = await contacts.contact(contactIdentifier)?.thumbnail,
              let image = UIImage(data: data)
        else { return }
        photo = Image(uiImage: image)
    }
}

// Injected the way every other boundary here is, so a preview or a test never reaches the real
// address book and nothing asks for permission until the user taps a row.
private struct ContactDirectoryKey: EnvironmentKey {
    static let defaultValue: any ContactDirectory = UnavailableContactDirectory()
}

extension EnvironmentValues {
    var contactDirectory: any ContactDirectory {
        get { self[ContactDirectoryKey.self] }
        set { self[ContactDirectoryKey.self] = newValue }
    }
}
