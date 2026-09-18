import Foundation

nonisolated enum ContactAccess: String, Sendable, Equatable {
    case notDetermined, denied, restricted, limited, authorized

    var canRead: Bool { self == .authorized || self == .limited }
}

// What the app is willing to know about a contact: enough to show who it is. The identifier is
// the only part that is ever stored; the name and the thumbnail are read live and held in memory,
// so Contacts stays the one copy of the user's address book.
nonisolated struct ContactMatch: Sendable, Equatable, Identifiable {
    let identifier: String
    let name: String
    let secondary: String?
    let thumbnail: Data?

    var id: String { identifier }
}

// Behind a protocol so tests never touch CNContactStore, the same shape every other injected
// boundary here uses (HTTPClient, TextGenerator, PageTranscriber). Not @MainActor: the store's
// fetches block, and a card render must not hold the main actor through one.
nonisolated protocol ContactDirectory: Sendable {
    var access: ContactAccess { get async }
    func requestAccess() async -> ContactAccess
    // Name components only, and never an empty query: CNContact's name predicate rejects one.
    func search(_ query: String) async -> [ContactMatch]
    func contact(_ identifier: String) async -> ContactMatch?
}

nonisolated struct UnavailableContactDirectory: ContactDirectory {
    var access: ContactAccess { get async { .denied } }
    func requestAccess() async -> ContactAccess { .denied }
    func search(_ query: String) async -> [ContactMatch] { [] }
    func contact(_ identifier: String) async -> ContactMatch? { nil }
}
