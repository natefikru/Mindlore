import SwiftUI

// "Which areas matter most to you right now?" Asked once on Life, changeable from the card and from
// Settings' Your journal. What Life does with the answer is compare it with where the writing went
// (`LifeSignals.priorities`): the gap between what someone says matters and what fills their pages
// is the most useful thing a journal can show them.
struct LifePrioritiesCard: View {
    @Environment(SettingsStore.self) private var settings
    let reading: LifeSignals.Reading
    @State private var picking = false

    var body: some View {
        Group {
            if settings.priorityAreas.isEmpty {
                if !settings.lifePrioritiesAsked { question }
            } else {
                answer
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                LifePrioritiesPicker(onDone: { picking = false })
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var question: some View {
        LifeCard(title: "What matters most right now?", symbol: "star", tint: Palette.ember) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick up to three areas. Life will show how much of your writing goes to them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Pick areas") { picking = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("lifePrioritiesPick")
                    Button("Not now") { settings.lifePrioritiesAsked = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("lifePrioritiesNotNow")
                }
            }
        }
        .accessibilityIdentifier("lifePrioritiesQuestion")
    }

    private var answer: some View {
        let priorities = LifeSignals.priorities(settings.priorityAreas, reading: reading, visibleCount: settings.visibleLifeAreas.count)
        return LifeCard(title: "What you said matters", symbol: "star.fill", tint: Palette.ember) {
            VStack(alignment: .leading, spacing: 14) {
                Text(LifeCopy.priorities(priorities, window: reading.window, name: settings.name(of:)))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lifePrioritiesSentence")
                ForEach(priorities) { priority in
                    LifePriorityBar(priority: priority, name: settings.name(of: priority.area))
                }
                Button("Change") { picking = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("lifePrioritiesChange")
            }
        }
        .accessibilityIdentifier("lifePriorities")
    }
}

private struct LifePriorityBar: View {
    let priority: LifeSignals.Priority
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(name, systemImage: priority.area.symbol)
                    .labelStyle(LifeTintedLabelStyle(tint: priority.area.color))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(LifeCopy.percent(priority.share))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(priority.isGap ? Palette.ember : .secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(priority.area.color.gradient)
                        .frame(width: max(6, geometry.size.width * min(1, priority.share)))
                    // Where an even spread would put it, so a short bar reads as short.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 1.5, height: 12)
                        .offset(x: geometry.size.width * min(1, priority.even) - 0.75)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// Up to three areas, in the order picked. Used from Life and from Settings.
struct LifePrioritiesPicker: View {
    @Environment(SettingsStore.self) private var settings
    var onDone: (() -> Void)?

    var body: some View {
        List {
            Section {
                ForEach(settings.visibleLifeAreas, id: \.self) { area in
                    let rank = settings.lifePriorities.firstIndex(of: area.rawValue)
                    Button {
                        toggle(area)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: area.symbol)
                                .foregroundStyle(area.color)
                                .frame(width: 26)
                            Text(settings.name(of: area))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if let rank {
                                Text("\(rank + 1)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Palette.ember, in: Circle())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(rank == nil && settings.lifePriorities.count >= LifeSignals.maxPriorities)
                    .accessibilityAddTraits(rank != nil ? .isSelected : [])
                    .accessibilityIdentifier("lifePriority-\(area.rawValue)")
                }
            } footer: {
                Text("Pick up to three. Life compares them with where your writing goes. Nothing here is shared or sent anywhere.")
            }
        }
        .paperBackground()
        .navigationTitle("What matters most")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("lifePrioritiesDone")
                }
            }
        }
        .sensoryFeedback(Haptics.selected, trigger: settings.lifePriorities)
        .onDisappear { settings.lifePrioritiesAsked = true }
    }

    private func toggle(_ area: LifeArea) {
        if let index = settings.lifePriorities.firstIndex(of: area.rawValue) {
            settings.lifePriorities.remove(at: index)
        } else if settings.lifePriorities.count < LifeSignals.maxPriorities {
            settings.lifePriorities.append(area.rawValue)
        }
    }
}
