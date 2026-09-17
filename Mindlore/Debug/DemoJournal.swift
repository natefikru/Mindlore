#if DEBUG
import Foundation
import SwiftData

// A made-up journal for building and measuring UI without recording weeks of entries. Launch a
// Debug build with `-seedDemoJournal <count>`: the app opens its own store, settings, and
// Keychain service, fills the store once, and indexes it through the real GraphIndexer.
// Release builds don't contain any of this.
enum DemoJournal {
    static let argument = "-seedDemoJournal"
    static let storeFileName = "demo-journal.store"

    static func requestedCount(in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let next = arguments.index(after: index)
        guard arguments.indices.contains(next), let count = Int(arguments[next]), count > 0 else { return 300 }
        return count
    }

    // Seeds only an empty store, so relaunching with the argument keeps whatever was changed.
    @discardableResult
    static func seedIfEmpty(count: Int, in context: ModelContext, now: Date = .now) throws -> Int {
        guard try context.fetchCount(FetchDescriptor<Entry>()) == 0 else { return 0 }
        let started = Date.now
        for draft in makeEntries(count: count, now: now) {
            insert(draft, in: context)
        }
        try context.save()
        GraphIndexer().sweep(in: context)
        DiagnosticsLog.shared.record("demo.seeded", [
            "entries": .int(count),
            "milliseconds": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ])
        return count
    }

    struct Draft: Equatable {
        var date: Date
        var title: String
        var text: String
        var summary: String
        var primaryMood: Mood
        var secondaryMood: Mood?
        var tags: [String]
        var mentions: [Mention]
    }

    // Deterministic for a given count and date: the same seed always writes the same journal.
    static func makeEntries(count: Int, now: Date) -> [Draft] {
        var random = SplitMix64(seed: UInt64(count))
        let cast = Cast(entryCount: count)
        let span: TimeInterval = 365 * 86_400
        return (0..<count).map { index in
            let offset = span * Double(count - index) / Double(count)
            let date = now.addingTimeInterval(-offset + Double(random.int(below: 6 * 3600)))
            return draft(on: date, cast: cast, random: &random)
        }
    }

    private static func draft(on date: Date, cast: Cast, random: inout SplitMix64) -> Draft {
        let people = random.distinctPicks(from: cast.people, count: 1 + random.int(below: 3))
        let place = random.chance(0.5) ? random.skewedPick(from: cast.places) : nil
        let organization = random.chance(0.3) ? random.skewedPick(from: cast.organizations) : nil
        let project = random.chance(0.3) ? random.skewedPick(from: cast.projects) : nil
        let event = random.chance(0.1) ? random.skewedPick(from: cast.events) : nil
        let tags = random.distinctPicks(from: cast.tags, count: 1 + random.int(below: 3))

        var sentences: [String] = []
        let others = people.dropFirst().joined(separator: " and ")
        sentences.append(random.element(of: [
            "Had a long talk with \(people[0])\(others.isEmpty ? "" : ", then caught up with \(others)").",
            "Spent most of the day with \(people[0])\(others.isEmpty ? "" : " and \(others)").",
            "\(people[0]) called this morning\(others.isEmpty ? "" : ", and later I saw \(others)").",
        ]))
        if let place { sentences.append("We ended up at \(place) for a while.") }
        if let organization { sentences.append("Things at \(organization) were busy again.") }
        if let project { sentences.append("Made some progress on \(project), slower than I hoped.") }
        if let event { sentences.append("Still thinking about \(event).") }
        sentences.append(random.element(of: [
            "I felt better by the evening.",
            "Hard to switch off tonight.",
            "Not much else to say about today.",
            "I want to remember how this felt.",
        ]))

        var mentions = people.map { Mention(name: $0, kindRaw: MentionKind.person.rawValue) }
        if let place { mentions.append(Mention(name: place, kindRaw: MentionKind.place.rawValue)) }
        if let organization { mentions.append(Mention(name: organization, kindRaw: MentionKind.organization.rawValue)) }
        if let project { mentions.append(Mention(name: project, kindRaw: MentionKind.project.rawValue)) }
        if let event { mentions.append(Mention(name: event, kindRaw: MentionKind.event.rawValue)) }

        let primary = random.element(of: Mood.allCases)
        let secondary = random.chance(0.4) ? random.element(of: Mood.allCases.filter { $0 != primary }) : nil
        return Draft(
            date: date,
            title: "\(date.formatted(.dateTime.weekday(.wide))) with \(people[0].split(separator: " ").first ?? "")",
            text: sentences.joined(separator: " "),
            summary: "Time with \(people[0])\(project.map { " and work on \($0)" } ?? "").",
            primaryMood: primary,
            secondaryMood: secondary,
            tags: tags,
            mentions: mentions
        )
    }

    // Past-dated and already past the automatic pass, so no AI job ever picks these up.
    private static func insert(_ draft: Draft, in context: ModelContext) {
        let entry = Entry(createdAt: draft.date, source: .typed, text: draft.text)
        entry.title = draft.title
        entry.titleWasGenerated = true
        entry.automaticAIPassUsed = true
        context.insert(entry)

        let insights = EntryInsights(
            generatedAt: draft.date.addingTimeInterval(60),
            modelUsed: "demo",
            sourceTextHash: TextHash.of(draft.text)
        )
        context.insert(insights)
        insights.entry = entry
        insights.summary = draft.summary
        insights.setMoods(primary: draft.primaryMood, secondary: draft.secondaryMood.map { [$0] } ?? [], editedByUser: false)
        insights.tags = draft.tags
        insights.mentions = draft.mentions
    }

    // Pool sizes grow with the entry count, so 300 entries give a graph of roughly 300 nodes.
    private struct Cast {
        let people: [String]
        let places: [String]
        let organizations: [String]
        let projects: [String]
        let events: [String]
        let tags: [String]

        init(entryCount count: Int) {
            let firsts = ["Sarah", "Marcus", "Priya", "Daniel", "Lena", "Omar", "Grace", "Theo", "Nadia", "Julian",
                          "Maya", "Isaac", "Chloe", "Rafael", "Hana", "Victor", "Zoe", "Elijah", "Amara", "Felix",
                          "Ruth", "Kenji", "Iris", "Mateo", "Leah", "Samuel", "Ines", "Caleb", "Yara", "Owen",
                          "Esme", "Tobias", "Noor", "Adrian", "Clara", "Desmond", "Mira", "Hugo", "Sofia", "Andre"]
            let lasts = ["Kim", "Okafor", "Patel", "Brooks", "Nguyen", "Haddad", "Silva", "Novak", "Reyes", "Lindqvist",
                         "Mensah", "Costa", "Tanaka", "Walsh", "Moreau", "Ibrahim", "Fischer", "Diaz", "Chen", "Hart",
                         "Sato", "Russo", "Kowalski", "Abara", "Quinn", "Varga", "Ortiz", "Byrne", "Das", "Frost"]
            let peopleCount = min(firsts.count * lasts.count, max(8, count * 45 / 100))
            // The surname offset varies within each block of first names but stays unique per pair.
            people = (0..<peopleCount).map { index in
                let first = index % firsts.count
                return "\(firsts[first]) \(lasts[(index / firsts.count + first * 7) % lasts.count])"
            }

            let placeStems = ["Cedar", "Harbor", "Maple", "Union", "Lakeview", "Juniper", "Granite", "Willow"]
            let placeKinds = ["Park", "Cafe", "Library", "Gym", "Market", "Station"]
            places = Self.combine(placeStems, placeKinds, limit: max(4, count / 6))

            let orgStems = ["Acme", "Northwind", "Brightline", "Fieldstone", "Parallel", "Kestrel"]
            let orgKinds = ["Labs", "Health", "Studio", "Group"]
            organizations = Self.combine(orgStems, orgKinds, limit: max(2, count / 12))

            projects = Array(["Marathon Training", "Kitchen Remodel", "Novel Draft", "Garden Beds", "Side App",
                              "Podcast Pilot", "Photo Book", "Spanish Course", "Job Search", "Tax Filing"]
                .prefix(max(2, count / 12)))
            events = Array(["Spring Retreat", "Family Reunion", "Quarterly Offsite", "Book Club Night",
                            "Housewarming Party", "City Hackathon"]
                .prefix(max(1, count / 20)))
            tags = Array(["work", "family", "friends", "health", "sleep", "running", "cooking", "money", "reading",
                          "travel", "music", "writing", "parenting", "therapy", "weekend", "mornings", "burnout",
                          "gratitude", "moving", "career", "dating", "garden", "coffee", "walks", "habits",
                          "planning", "meetings", "deadlines", "learning", "home", "chores", "weather", "focus",
                          "phone", "social", "anxiety", "rest", "exercise", "creativity", "podcasts", "movies",
                          "birthdays", "holidays", "pets", "neighbors", "commute", "budget", "goals", "memories",
                          "volunteering"]
                .prefix(max(6, count / 6)))
        }

        private static func combine(_ stems: [String], _ kinds: [String], limit: Int) -> [String] {
            let all = kinds.flatMap { kind in stems.map { "\($0) \(kind)" } }
            return Array(all.prefix(limit))
        }
    }
}

// A small seeded generator, so the demo journal is identical on every run.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func int(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func element<T>(of items: [T]) -> T {
        items[int(below: items.count)]
    }

    // Skewed toward the front of the list, so a few names recur often, the way a real cast does.
    mutating func skewedPick(from items: [String]) -> String {
        items[min(items.count - 1, Int(pow(unit(), 2.2) * Double(items.count)))]
    }

    mutating func distinctPicks(from items: [String], count: Int) -> [String] {
        var picked: [String] = []
        var attempts = 0
        while picked.count < min(count, items.count), attempts < count * 10 {
            let item = skewedPick(from: items)
            if !picked.contains(item) { picked.append(item) }
            attempts += 1
        }
        return picked.isEmpty ? [items[0]] : picked
    }
}
#endif
