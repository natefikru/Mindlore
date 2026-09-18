import Contacts
import Foundation

// The real address book. Only three keys are ever fetched, so nothing else can leak: the
// identifier the app stores, the formatted name, and the thumbnail. No phone number, no email,
// no address, no note.
nonisolated final class CNContactDirectory: ContactDirectory {
    private let store = CNContactStore()
    private let cache = ThumbnailCache()

    private static let maxResults = 25

    private var keys: [any CNKeyDescriptor] {
        [
            CNContactIdentifierKey as any CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactThumbnailImageDataKey as any CNKeyDescriptor,
        ]
    }

    var access: ContactAccess {
        get async { Self.access(CNContactStore.authorizationStatus(for: .contacts)) }
    }

    static func access(_ status: CNAuthorizationStatus) -> ContactAccess {
        switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    @concurrent func requestAccess() async -> ContactAccess {
        // A throw here means denied, which the status read below reports anyway.
        _ = try? await store.requestAccess(for: .contacts)
        return await access
    }

    @concurrent func search(_ query: String) async -> [ContactMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // CNContact's name predicate rejects an empty string, and matching everything is not
        // something this app should do anyway.
        guard !trimmed.isEmpty, await access.canRead else { return [] }
        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        return fetch(predicate).prefix(Self.maxResults).map { $0 }
    }

    @concurrent func contact(_ identifier: String) async -> ContactMatch? {
        guard await access.canRead else { return nil }
        if let cached = await cache.match(for: identifier) { return cached }
        let found = fetch(CNContact.predicateForContacts(withIdentifiers: [identifier])).first
        if let found { await cache.store(found) }
        return found
    }

    private func fetch(_ predicate: NSPredicate) -> [ContactMatch] {
        let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return contacts.map(Self.match)
    }

    static func match(_ contact: CNContact) -> ContactMatch {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ContactMatch(
            identifier: contact.identifier,
            name: formatted.isEmpty ? "No name" : formatted,
            thumbnail: contact.thumbnailImageData
        )
    }
}

// Small and per-session: a card asks for the same person every time it opens, and the address
// book is the copy of record, so nothing here outlives the launch.
private actor ThumbnailCache {
    private var byIdentifier: [String: ContactMatch] = [:]
    private var order: [String] = []
    private let limit = 50

    func match(for identifier: String) -> ContactMatch? { byIdentifier[identifier] }

    func store(_ match: ContactMatch) {
        if byIdentifier[match.identifier] == nil { order.append(match.identifier) }
        byIdentifier[match.identifier] = match
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            byIdentifier[oldest] = nil
        }
    }
}
