import Contacts
import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A fake address book, so no test ever touches CNContactStore or asks for permission.
final class FakeContactDirectory: ContactDirectory, @unchecked Sendable {
    var granted: ContactAccess
    var contacts: [ContactMatch]
    private(set) var requests = 0
    private(set) var searches: [String] = []

    init(granted: ContactAccess = .authorized, contacts: [ContactMatch] = []) {
        self.granted = granted
        self.contacts = contacts
    }

    var access: ContactAccess { get async { granted } }

    func requestAccess() async -> ContactAccess {
        requests += 1
        if granted == .notDetermined { granted = .authorized }
        return granted
    }

    func search(_ query: String) async -> [ContactMatch] {
        searches.append(query)
        guard granted.canRead, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func contact(_ identifier: String) async -> ContactMatch? {
        guard granted.canRead else { return nil }
        return contacts.first { $0.identifier == identifier }
    }
}

@MainActor
struct ContactLinkTests {
    let harness: GraphHarness
    let editor = GraphEditor(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    private func person(_ name: String = "Sarah") throws -> Entity {
        let entity = Entity(name: name, key: EntityNormalizer.key(for: name, kind: .person), kind: .person)
        harness.context.insert(entity)
        try harness.context.save()
        return entity
    }

    @Test func linkingStoresOnlyTheIdentifier() throws {
        let sarah = try person()

        #expect(editor.linkContact(sarah, identifier: "ABC-123", in: harness.context) == .applied)

        #expect(sarah.contactIdentifier == "ABC-123")
        // Nothing about the contact itself: the address book stays the one copy.
        #expect(sarah.name == "Sarah")
        #expect(sarah.bio == nil)
    }

    @Test func linkingClaimsTheEntitySoItSurvivesLosingItsLinks() throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)
        #expect(sarah.confirmedByUser)
    }

    @Test func unlinkingClearsIt() throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)

        #expect(editor.unlinkContact(sarah, in: harness.context) == .applied)
        #expect(sarah.contactIdentifier == nil)
    }

    @Test func onlyAPersonCanLinkAContact() throws {
        let place = Entity(name: "Harbor Coffee", key: "harbor coffee", kind: .place)
        harness.context.insert(place)

        editor.linkContact(place, identifier: "ABC-123", in: harness.context)

        #expect(place.contactIdentifier == nil)
    }

    @Test func changingAwayFromPersonDropsTheLink() throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)

        #expect(editor.setKind(.organization, on: sarah, in: harness.context) == .applied)
        #expect(sarah.contactIdentifier == nil)
    }

    // setKind returns before touching anything when a name collides, so the link has to survive
    // the path that never applied the change.
    @Test func aCollidingKindChangeLeavesTheLinkAlone() throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)
        let clash = Entity(name: "Sarah", key: EntityNormalizer.key(for: "Sarah", kind: .organization), kind: .organization)
        harness.context.insert(clash)
        try harness.context.save()

        #expect(editor.setKind(.organization, on: sarah, in: harness.context) == .collides(with: clash.id))
        #expect(sarah.contactIdentifier == "ABC-123", "the kind never changed, so neither did the link")
        #expect(sarah.kind == .person)
    }

    // Deleted from the phone, or access narrowed since. Either way the identifier is kept:
    // granting access again brings the contact back.
    @Test func aContactTheAppCannotReadIsNotUnlinkedByItself() async throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "GONE", in: harness.context)
        let directory = FakeContactDirectory(contacts: [])

        #expect(await directory.contact("GONE") == nil)
        #expect(sarah.contactIdentifier == "GONE")
    }

    @Test func deniedAccessLeavesTheEntityUsable() async throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)
        let directory = FakeContactDirectory(granted: .denied, contacts: [
            ContactMatch(identifier: "ABC-123", name: "Sarah Kim", thumbnail: nil)
        ])

        #expect(await directory.contact("ABC-123") == nil)
        #expect(await directory.search("Sarah").isEmpty)
        #expect(sarah.name == "Sarah", "the journal does not depend on the address book")
    }

    // Limited access is a real state on iOS 18 and later: the search sees only what was granted.
    @Test func limitedAccessStillReads() async throws {
        let directory = FakeContactDirectory(granted: .limited, contacts: [
            ContactMatch(identifier: "ABC-123", name: "Sarah Kim", thumbnail: nil)
        ])

        #expect(await directory.contact("ABC-123")?.name == "Sarah Kim")
        #expect(await directory.search("Sarah").count == 1)
    }

    // CNContact's name predicate rejects an empty string, and matching everyone is not something
    // this app should ever do.
    @Test func anEmptyQueryFindsNothing() async throws {
        let directory = FakeContactDirectory(contacts: [
            ContactMatch(identifier: "ABC-123", name: "Sarah Kim", thumbnail: nil)
        ])

        #expect(await directory.search("").isEmpty)
        #expect(await directory.search("   ").isEmpty)
    }

    @Test func theSummaryCarriesTheContactForTheCard() throws {
        let sarah = try person()
        editor.linkContact(sarah, identifier: "ABC-123", in: harness.context)
        try harness.context.save()
        let graph = GraphServices(diagnostics: .disabled)

        let summary = EntityPeekPresentation.load(sarah.id, graph: graph, in: harness.context)

        #expect(summary?.contactIdentifier == "ABC-123")
    }

    @Test func everyAuthorizationStatusMapsToAnAccess() {
        #expect(CNContactDirectory.access(.authorized) == .authorized)
        #expect(CNContactDirectory.access(.limited) == .limited)
        #expect(CNContactDirectory.access(.denied) == .denied)
        #expect(CNContactDirectory.access(.restricted) == .restricted)
        #expect(CNContactDirectory.access(.notDetermined) == .notDetermined)
        #expect(ContactAccess.authorized.canRead && ContactAccess.limited.canRead)
        #expect(!ContactAccess.denied.canRead && !ContactAccess.notDetermined.canRead)
    }
}
