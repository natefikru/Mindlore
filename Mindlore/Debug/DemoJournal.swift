#if DEBUG
import Foundation
import SwiftData

// A made-up journal for building and measuring UI without recording weeks of entries. Launch a
// Debug build with `-seedDemoJournal <count>`: the app opens its own store, settings, and
// Keychain service, fills the store once, and indexes it through the real GraphIndexer.
// Release builds don't contain any of this.
//
// Each entry is a scene (a work day, a call with family, a run) that decides together who is in
// it, where it happened, what it was about, and how it felt, so the names, tags, area, and mood
// the insights carry are all things the text actually says. Loose ends are sentences in the text
// too, and a later entry settles one by saying so.
enum DemoJournal {
    static let argument = "-seedDemoJournal"
    static let resetSettingsArgument = "-resetDemoSettings"
    static let settingsSuiteName = "demo-journal"
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
        let drafts = makeEntries(count: count, now: now)
        let entries = drafts.map { insert($0, in: context) }
        try context.save()
        GraphIndexer().sweep(in: context)
        seedLooseEnds(drafts: drafts, entries: entries, in: context, now: now)
        try context.save()
        DiagnosticsLog.shared.record("demo.seeded", [
            "entries": .int(count),
            "milliseconds": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ])
        return count
    }

    // Writes the loose ends the drafts' own sentences describe. The writer's 42-day rule fades
    // the old ones, so the recent ones are the ones left open.
    private static func seedLooseEnds(drafts: [Draft], entries: [Entry], in context: ModelContext, now: Date) {
        var created: [Int: UUID] = [:]
        for (index, (draft, entry)) in zip(drafts, entries).enumerated() {
            var result = LooseEndResult()
            if let thread = draft.opens {
                result.new = [.init(text: thread.looseEnd, about: [thread.person])]
            }
            if let opener = draft.settles, let id = created[opener] {
                result.resolved = [id]
            }
            guard !result.isEmpty else { continue }
            LooseEndWriter.apply(result, to: entry, in: context, now: now)
            if draft.opens != nil {
                let entryID = entry.id
                created[index] = LooseEnd.all(in: context).first { $0.sourceEntryID == entryID }?.id
            }
        }
    }

    struct Thread: Equatable {
        let person: String
        let opened: String
        let looseEnd: String
        let settled: String
    }

    struct Draft: Equatable {
        var date: Date
        var title: String
        var text: String
        var summary: String
        var primaryMood: Mood
        var secondaryMood: Mood?
        var areas: [LifeArea]
        var tags: [String]
        var mentions: [Mention]
        // A thread this entry leaves open, and the index of an earlier entry whose thread it settles.
        var opens: Thread?
        var settles: Int?
    }

    // Deterministic for a given count and date: the same seed always writes the same journal.
    static func makeEntries(count: Int, now: Date) -> [Draft] {
        var random = SplitMix64(seed: UInt64(count))
        let cast = Cast(entryCount: count)
        let span: TimeInterval = 365 * 86_400
        var drafts: [Draft] = []
        var waiting: [(opener: Int, thread: Thread)] = []
        for index in 0..<count {
            let offset = span * Double(count - index) / Double(count)
            let date = now.addingTimeInterval(-offset + Double(random.int(below: 6 * 3600)))
            var draft = draft(on: date, cast: cast, random: &random)
            // Every sixth entry leaves something open; every other one of those is settled four
            // entries later, the rest are left to stay open or fade.
            if let settling = waiting.first, index - settling.opener >= 4 {
                waiting.removeFirst()
                settle(settling.thread, opener: settling.opener, in: &draft)
            } else if index % 6 == 0 {
                let thread = cast.thread(for: draft, index: index)
                draft.text += " " + thread.opened
                draft.opens = thread
                if index % 12 == 0 { waiting.append((index, thread)) }
            }
            drafts.append(draft)
        }
        return drafts.sorted { $0.date < $1.date }
    }

    private static func settle(_ thread: Thread, opener: Int, in draft: inout Draft) {
        draft.text += " " + thread.settled
        draft.settles = opener
        if !draft.mentions.contains(where: { $0.name == thread.person }) {
            draft.mentions.append(Mention(name: thread.person, kindRaw: MentionKind.person.rawValue))
        }
    }

    private static func draft(on date: Date, cast: Cast, random: inout SplitMix64) -> Draft {
        let scene = random.element(of: Scene.weighted)
        let pool = cast.people(for: scene.kind)
        var people = random.distinctPicks(from: pool, count: 1 + random.int(below: scene.maxPeople))
        if scene.kind == .love { people = [cast.partner] }
        let lead = people[0]
        let leadFirst = String(lead.split(separator: " ").first ?? "")
        let others = people.dropFirst().joined(separator: " and ")
        let organization = scene.kind == .work ? cast.organization(of: lead) : nil
        let places = cast.places(for: scene.kind)
        let place = !places.isEmpty && random.chance(0.6) ? random.skewedPick(from: places) : nil
        let project = !scene.projects.isEmpty && random.chance(0.4) ? random.element(of: Array(scene.projects.prefix(cast.projectLimit))) : nil
        let event = !scene.events.isEmpty && random.chance(0.12) ? random.element(of: Array(scene.events.prefix(cast.eventLimit))) : nil
        let topicCount = 1 + random.int(below: 2)
        let topics = random.distinctPicks(from: scene.topics.map(\.sentence), count: topicCount)
            .compactMap { sentence in scene.topics.first { $0.sentence == sentence } }

        var sentences = [String(format: random.element(of: scene.openers), lead, organization ?? "")]
        if !others.isEmpty { sentences.append("\(others) \(people.count > 2 ? "were" : "was") there too.") }
        if let place { sentences.append(String(format: random.element(of: scene.placeLines), place)) }
        if let project { sentences.append(String(format: random.element(of: scene.projectLines), project)) }
        if let event { sentences.append("Still thinking about \(event).") }
        sentences += topics.map(\.sentence)

        var mentions = people.map { Mention(name: $0, kindRaw: MentionKind.person.rawValue) }
        if let organization { mentions.append(Mention(name: organization, kindRaw: MentionKind.organization.rawValue)) }
        if let place { mentions.append(Mention(name: place, kindRaw: MentionKind.place.rawValue)) }
        if let project { mentions.append(Mention(name: project, kindRaw: MentionKind.project.rawValue)) }
        if let event { mentions.append(Mention(name: event, kindRaw: MentionKind.event.rawValue)) }

        var areas = [scene.kind]
        areas += topics.compactMap(\.area)
        areas = Array(areas.reduce(into: [LifeArea]()) { if !$0.contains($1) { $0.append($1) } }.prefix(LifeArea.maxPerEntry))

        let moods = topics.map(\.mood)
        return Draft(
            date: date,
            title: "\(scene.title) with \(leadFirst)",
            text: sentences.joined(separator: " "),
            summary: "\(scene.summary) with \(leadFirst)\(project.map { ", and \($0)" } ?? "").",
            primaryMood: moods[0],
            secondaryMood: moods.dropFirst().first { $0 != moods[0] },
            areas: areas,
            tags: topics.flatMap(\.tags),
            mentions: mentions
        )
    }

    // Past-dated and already past the automatic pass, so no AI job ever picks these up.
    @discardableResult
    private static func insert(_ draft: Draft, in context: ModelContext) -> Entry {
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
        insights.areas = draft.areas
        insights.tags = draft.tags
        insights.mentions = draft.mentions
        return entry
    }

    // A sentence written around its tags, so every tag an entry carries is a word in it. No tag is
    // a life area's name, since insights drop those. The mood is the one the sentence describes.
    struct Topic {
        let sentence: String
        let tags: [String]
        let mood: Mood
        var area: LifeArea?
    }

    struct Scene {
        let kind: LifeArea
        let title: String
        let summary: String
        var maxPeople = 2
        // %1$@ is the lead person, %2$@ their organization (work only).
        let openers: [String]
        var placeLines: [String] = []
        var projectLines: [String] = []
        var projects: [String] = []
        var events: [String] = []
        let topics: [Topic]

        // Uneven on purpose, like a real journal: work and friends dominate, money is rare.
        static let weighted: [Scene] = [work, work, work, work, friends, friends, friends, family, family,
                                        mind, mind, health, health, love, love, play, play, home, money]

        static let work = Scene(
            kind: .work, title: "Work", summary: "A work day",
            openers: ["Long day at %2$@. %1$@ and I went back and forth on the details.",
                      "%1$@ pulled me into a meeting at %2$@ that ran an hour over.",
                      "Pairing with %1$@ most of the afternoon at %2$@."],
            projectLines: ["We made some progress on the %@, slower than I hoped.", "The %@ slipped another week."],
            projects: ["Billing Redesign", "Onboarding Revamp", "Data Migration", "Search Rewrite"],
            events: ["Quarterly Offsite", "City Hackathon"],
            topics: [
                Topic(sentence: "Back-to-back meetings until five.", tags: ["meetings"], mood: .tired),
                Topic(sentence: "Two deadlines landed on the same day.", tags: ["deadlines"], mood: .stressed),
                Topic(sentence: "Burnout is creeping in again.", tags: ["burnout"], mood: .burnedOut, area: .mind),
                Topic(sentence: "Thinking about my career and where it is going.", tags: ["career"], mood: .uncertain),
                Topic(sentence: "Shipping the thing we'd been stuck on felt great, and the team cheered.", tags: ["shipping"], mood: .proud),
                Topic(sentence: "The feedback on my review was better than I feared.", tags: ["feedback"], mood: .relieved),
                Topic(sentence: "Got interrupted every ten minutes and my focus never came back.", tags: ["focus"], mood: .frustrated),
            ]
        )

        static let family = Scene(
            kind: .family, title: "Family", summary: "Time with family",
            openers: ["Called %1$@ this evening.", "%1$@ came over for dinner.", "Drove out to see %1$@."],
            placeLines: ["We walked around %@ after lunch.", "Met at %@ halfway."],
            events: ["Family Reunion", "Grandpa's Memorial"],
            topics: [
                Topic(sentence: "Parenting advice I didn't ask for, again.", tags: ["parenting"], mood: .irritated),
                Topic(sentence: "Two birthdays this week and no gifts yet.", tags: ["birthdays"], mood: .stressed),
                Topic(sentence: "We looked at old photos and laughed about the memories.", tags: ["memories"], mood: .nostalgic),
                Topic(sentence: "The phone call ended better than it started.", tags: ["phone"], mood: .relieved),
                Topic(sentence: "Their loneliness since the move stayed with me.", tags: ["loneliness"], mood: .sad),
            ]
        )

        static let friends = Scene(
            kind: .friends, title: "Coffee", summary: "Catching up",
            maxPeople: 3,
            openers: ["Met %1$@ for coffee.", "Caught up with %1$@ after work.", "%1$@ texted out of nowhere and we ended up getting dinner."],
            placeLines: ["We sat at %@ until they closed.", "Ended up at %@ for a while."],
            events: ["Book Club Night", "Housewarming Party"],
            topics: [
                Topic(sentence: "Too much coffee, too much talking, all good.", tags: ["coffee"], mood: .joyful),
                Topic(sentence: "We took one of our long walks and talked about nothing, which was the point.", tags: ["walks"], mood: .connected),
                Topic(sentence: "Spent the morning volunteering at the food bank together.", tags: ["volunteering"], mood: .grateful),
                Topic(sentence: "We argued about movies for an hour.", tags: ["movies"], mood: .joyful, area: .play),
                Topic(sentence: "They're going through a rough patch, so I mostly listened and offered support.", tags: ["support"], mood: .compassionate),
            ]
        )

        static let love = Scene(
            kind: .love, title: "Evening", summary: "An evening at home",
            maxPeople: 1,
            openers: ["Quiet evening with %1$@.", "%1$@ and I finally had a proper night in.", "Small fight with %1$@ about nothing, then we made up."],
            topics: [
                Topic(sentence: "We cooked together; cooking is still the best part of our week.", tags: ["cooking"], mood: .loved, area: .home),
                Topic(sentence: "Started planning the summer travel, which already feels good.", tags: ["travel", "planning"], mood: .excited, area: .play),
                Topic(sentence: "A slow weekend, which we both needed.", tags: ["weekend"], mood: .content),
                Topic(sentence: "We talked about whether to have kids and didn't land anywhere.", tags: ["kids"], mood: .conflicted),
            ]
        )

        static let health = Scene(
            kind: .health, title: "Run", summary: "A run",
            openers: ["Ran with %1$@ after work.", "%1$@ talked me into the early group run.", "Checkup with %1$@ this morning."],
            placeLines: ["Did the loop around %@.", "Finished at %@ and stretched for a bit."],
            projectLines: ["The %@ plan says ten miles this weekend.", "Behind on the %@ schedule."],
            projects: ["Marathon Training"],
            topics: [
                Topic(sentence: "Slept badly, and the lack of sleep caught up with me.", tags: ["sleep"], mood: .tired),
                Topic(sentence: "Went running before breakfast and felt great after.", tags: ["running"], mood: .energized),
                Topic(sentence: "Got some real rest this afternoon.", tags: ["rest"], mood: .calm),
                Topic(sentence: "The knee injury flared up again on the hills.", tags: ["injury"], mood: .frustrated),
            ]
        )

        static let mind = Scene(
            kind: .mind, title: "Session", summary: "A therapy session",
            maxPeople: 1,
            openers: ["Session with %1$@ today.", "Told %1$@ about the week and it came out messier than I expected."],
            topics: [
                Topic(sentence: "Therapy was useful, we talked about old patterns.", tags: ["therapy"], mood: .reflective),
                Topic(sentence: "Wrote down three things for gratitude before bed.", tags: ["gratitude"], mood: .grateful),
                Topic(sentence: "Some anxiety before the call, then it went fine.", tags: ["anxiety"], mood: .anxious),
                Topic(sentence: "Trying to build better habits around my phone.", tags: ["habits", "phone"], mood: .hopeful),
                Topic(sentence: "Did some writing before anyone else was up.", tags: ["writing"], mood: .calm),
            ]
        )

        static let home = Scene(
            kind: .home, title: "Home", summary: "Things around the house",
            maxPeople: 1,
            openers: ["%1$@ from downstairs stopped by.", "%1$@ came to look at the leak."],
            placeLines: ["Picked up groceries at %@ on the way back."],
            projectLines: ["Another weekend on the %@.", "The %@ is finally looking like something."],
            projects: ["Kitchen Remodel", "Garden Beds"],
            topics: [
                Topic(sentence: "Chores took most of the evening.", tags: ["chores"], mood: .bored),
                Topic(sentence: "Still sorting boxes from moving.", tags: ["moving"], mood: .overwhelmed),
                Topic(sentence: "The pets woke me up at five.", tags: ["pets"], mood: .tired),
                Topic(sentence: "Spent an hour in the garden pulling weeds.", tags: ["garden"], mood: .content, area: .play),
                Topic(sentence: "Chatted with the neighbors over the fence.", tags: ["neighbors"], mood: .connected),
            ]
        )

        static let play = Scene(
            kind: .play, title: "Afternoon", summary: "A free afternoon",
            openers: ["Spent the afternoon with %1$@.", "%1$@ dragged me to a show, glad they did."],
            placeLines: ["Browsed %@ for an hour.", "Wandered through %@."],
            projectLines: ["Put another hour into the %@.", "Picked the %@ back up after weeks away."],
            projects: ["Novel Draft", "Photo Book", "Spanish Course"],
            topics: [
                Topic(sentence: "Stayed up reading a novel I can't put down.", tags: ["reading"], mood: .content),
                Topic(sentence: "Put on some music and forgot about the week.", tags: ["music"], mood: .joyful),
                Topic(sentence: "Learning a bit of guitar each night, badly.", tags: ["guitar", "learning"], mood: .curious),
                Topic(sentence: "Listened to podcasts on the long drive.", tags: ["podcasts"], mood: .calm),
            ]
        )

        static let money = Scene(
            kind: .money, title: "Budget", summary: "Going over money",
            maxPeople: 1,
            openers: ["Sat down with %1$@ to go over the numbers.", "%1$@ helped me sort out the paperwork."],
            projectLines: ["The %@ is due soon and I've barely started."],
            projects: ["Tax Filing"],
            topics: [
                Topic(sentence: "Went over the budget and it looks tight.", tags: ["budget"], mood: .anxious),
                Topic(sentence: "Paid off the last of the card debt.", tags: ["debt"], mood: .relieved),
                Topic(sentence: "Rent is going up again.", tags: ["rent"], mood: .stressed, area: .home),
            ]
        )
    }

    // Pool sizes grow with the entry count, so 300 entries give a busy graph. People are split by
    // the part of life they belong to, so a coworker always turns up at work and at the same
    // organization.
    private struct Cast {
        let partner: String
        private let pools: [LifeArea: [String]]
        private let organizations: [String]
        private let placesByKind: [LifeArea: [String]]
        let projectLimit: Int
        let eventLimit: Int

        init(entryCount count: Int) {
            let firsts = ["Sarah", "Marcus", "Priya", "Daniel", "Lena", "Omar", "Grace", "Theo", "Nadia", "Julian",
                          "Maya", "Isaac", "Chloe", "Rafael", "Hana", "Victor", "Zoe", "Elijah", "Amara", "Felix",
                          "Ruth", "Kenji", "Iris", "Mateo", "Leah", "Samuel", "Ines", "Caleb", "Yara", "Owen",
                          "Esme", "Tobias", "Noor", "Adrian", "Clara", "Desmond", "Mira", "Hugo", "Sofia", "Andre"]
            let lasts = ["Kim", "Okafor", "Patel", "Brooks", "Nguyen", "Haddad", "Silva", "Novak", "Reyes", "Lindqvist",
                         "Mensah", "Costa", "Tanaka", "Walsh", "Moreau", "Ibrahim", "Fischer", "Diaz", "Chen", "Hart",
                         "Sato", "Russo", "Kowalski", "Abara", "Quinn", "Varga", "Ortiz", "Byrne", "Das", "Frost"]
            let peopleCount = min(firsts.count * lasts.count, max(16, count * 45 / 100))
            // The surname offset varies within each block of first names but stays unique per pair.
            let people = (0..<peopleCount).map { index in
                let first = index % firsts.count
                return "\(firsts[first]) \(lasts[(index / firsts.count + first * 7) % lasts.count])"
            }
            partner = people[0]
            // Work and friends get the most people; a therapist, a landlord, and an accountant are few.
            let shares: [(LifeArea, Int)] = [(.work, 30), (.friends, 25), (.family, 15), (.health, 10), (.play, 10),
                                             (.home, 4), (.mind, 3), (.money, 3)]
            var pools: [LifeArea: [String]] = [:]
            var cursor = 1
            for (index, (area, share)) in shares.enumerated() {
                let size = index == shares.count - 1 ? people.count - cursor : max(1, (people.count - 1) * share / 100)
                pools[area] = Array(people[cursor..<min(people.count, cursor + size)])
                cursor = min(people.count - 1, cursor + size)
            }
            pools[.love] = [partner]
            self.pools = pools

            let orgStems = ["Acme", "Northwind", "Brightline", "Fieldstone", "Parallel", "Kestrel"]
            let orgKinds = ["Labs", "Health", "Studio", "Group"]
            organizations = Self.combine(orgStems, orgKinds, limit: max(2, count / 40))

            let stems = ["Cedar", "Harbor", "Maple", "Union", "Lakeview", "Juniper", "Granite", "Willow"]
            let limit = max(2, count / 30)
            placesByKind = [
                .friends: Self.combine(stems, ["Cafe", "Park"], limit: limit),
                .health: Self.combine(stems.reversed(), ["Park", "Gym"], limit: limit),
                .family: Self.combine(stems, ["Station", "Park"], limit: max(1, limit / 2)),
                .home: Self.combine(stems, ["Market"], limit: max(1, limit / 2)),
                .play: Self.combine(stems, ["Library", "Bookshop"], limit: limit),
            ]
            projectLimit = max(1, count / 60)
            eventLimit = max(1, count / 120)
        }

        func people(for area: LifeArea) -> [String] {
            let pool = pools[area] ?? []
            return pool.isEmpty ? [partner] : pool
        }

        func places(for area: LifeArea) -> [String] {
            placesByKind[area] ?? []
        }

        func organization(of person: String) -> String {
            organizations[abs(person.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % organizations.count]
        }

        // Something concrete a later entry could settle, about the entry's lead person.
        func thread(for draft: Draft, index: Int) -> Thread {
            let person = draft.mentions.first { $0.kind == .person }?.name ?? partner
            let first = String(person.split(separator: " ").first ?? "")
            let threads = [
                Thread(person: person, opened: "Still waiting to hear back from \(first) about the plan.",
                       looseEnd: "Hear back from \(first) about the plan", settled: "\(person) finally got back to me about the plan."),
                Thread(person: person, opened: "I need to decide whether to take \(first) up on the offer.",
                       looseEnd: "Decide on \(first)'s offer", settled: "Told \(person) yes, so that's decided."),
                Thread(person: person, opened: "Promised \(first) I'd send the photos this week.",
                       looseEnd: "Send \(first) the photos", settled: "Sent \(person) the photos at last."),
            ]
            return threads[(index / 6) % threads.count]
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
