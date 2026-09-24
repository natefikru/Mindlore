import Foundation

// Every sentence Life says before any model words it, from the numbers alone. Plain, second person,
// about situations and never traits ("Work has been heavier than your usual", never "you are
// stressed"), and about what's on the author's mind rather than their life, since how much someone
// writes about a thing is not how much time it takes.
nonisolated enum LifeCopy {
    typealias Name = (LifeArea) -> String

    static func windowPhrase(_ window: MindWindow) -> String {
        switch window {
        case .month: "this month"
        case .quarter: "these three months"
        case .year: "this year"
        case .all: "so far"
        }
    }

    static func previousPhrase(_ window: MindWindow) -> String {
        switch window {
        case .month: "the month before"
        case .quarter: "the three months before"
        case .year: "the year before"
        case .all: "before"
        }
    }

    static func headline(_ headline: LifeSignals.Headline, window: MindWindow, name: Name) -> String {
        let names = headline.areas.map(name)
        let subject = names.count > 1 ? "\(names[0]) and \(names[1])" : names[0]
        let base = "Mostly \(subject) \(windowPhrase(window))"
        switch headline.tone {
        case .heavier: return "\(base), and heavier than your usual."
        case .lighter: return "\(base), and lighter than your usual."
        case nil: return "\(base)."
        }
    }

    // "From 64 entries since 24 June."
    static func basis(entries: Int, since start: Date, locale: Locale = .current) -> String {
        let day = start.formatted(Date.FormatStyle(locale: locale).day().month(.wide))
        return "From \(entries) \(entries == 1 ? "entry" : "entries") since \(day)."
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    static func areaLine(_ reading: LifeSignals.AreaReading, name: Name) -> String {
        let feel: String
        switch reading.height {
        case let height? where height >= 0.15: feel = "lighter than your usual"
        case let height? where height <= -0.15: feel = "heavier than your usual"
        case .some: feel = "about your usual"
        case nil: feel = "too few moods to say how it felt"
        }
        return "\(reading.entries) \(reading.entries == 1 ? "entry" : "entries"), \(feel)"
    }

    static func recurringDetail(_ recurring: LifeSignals.Recurring) -> String {
        let unit = recurring.periodIsMonth ? "months" : "weeks"
        return "In \(recurring.periods) different \(unit), \(recurring.entries) \(recurring.entries == 1 ? "entry" : "entries")"
    }

    static func quiet(_ quiet: LifeSignals.Quiet, window: MindWindow, name: Name) -> String {
        "\(name(quiet.area)) was \(percent(quiet.shareBefore)) of what you wrote \(previousPhrase(window)), and \(percent(quiet.shareNow)) since."
    }

    static func change(_ change: LifeSignals.Change, window: MindWindow, name: Name) -> String {
        switch change.kind {
        case .share(let before, let now):
            return "\(name(change.area)) went from \(percent(before)) to \(percent(now)) of what you wrote."
        case .tone(.lighter):
            return "\(name(change.area)) has felt lighter than \(previousPhrase(window))."
        case .tone(.heavier):
            return "\(name(change.area)) has felt heavier than \(previousPhrase(window))."
        }
    }

    static func contrast(_ contrast: LifeSignals.Contrast, name: Name) -> String {
        let closes = contrast.closes
        let fades = contrast.fades
        var first = "You close what comes up in \(name(closes.area)): \(closes.resolved) of \(closes.closed) done"
        if let days = closes.medianDaysToResolve {
            first += days <= 1 ? ", usually within a day" : ", in about \(days) days"
        }
        let second = "\(name(fades.area)) threads tend to fade: \(fades.faded) of \(fades.closed)."
        return "\(first). \(second)"
    }

    static func followLine(_ follow: LifeSignals.FollowThrough) -> String {
        var parts = ["\(follow.resolved) done"]
        if follow.faded > 0 { parts.append("\(follow.faded) faded") }
        if follow.dismissed > 0 { parts.append("\(follow.dismissed) let go") }
        var line = parts.joined(separator: ", ")
        if let days = follow.medianDaysToResolve, follow.resolved > 0 {
            line += days <= 1 ? " · closed within a day" : " · about \(days) days to close"
        }
        return line
    }

    static func priorities(_ priorities: [LifeSignals.Priority], window: MindWindow, name: Name) -> String {
        let gaps = priorities.filter(\.isGap)
        let names = priorities.map { name($0.area) }
        guard let first = gaps.first else {
            return "Your writing \(windowPhrase(window)) follows what you said matters: \(listed(names))."
        }
        if first.share == 0 {
            return "You said \(name(first.area)) matters to you right now. You haven't written about it \(windowPhrase(window))."
        }
        return "You said \(name(first.area)) matters to you right now. It's been \(percent(first.share)) of what you wrote \(windowPhrase(window))."
    }

    static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    static func needsMore(_ progress: LifeSignals.Progress) -> String {
        let entries = max(0, LifeSignals.minimumEntries - progress.entries)
        let days = max(0, LifeSignals.minimumDays - progress.days)
        if entries > 0 && days > 0 {
            return "Life reads a few weeks of you. \(entries) more \(entries == 1 ? "entry" : "entries") and \(days) more \(days == 1 ? "day" : "days") of journal, and it starts."
        } else if entries > 0 {
            return "Life reads a few weeks of you. \(entries) more \(entries == 1 ? "entry" : "entries"), and it starts."
        }
        return "Life reads a few weeks of you. \(days) more \(days == 1 ? "day" : "days") of journal, and it starts."
    }
}
