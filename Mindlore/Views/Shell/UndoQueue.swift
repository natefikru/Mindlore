import SwiftUI

// A delete that waits a few seconds before it happens, so a stray swipe can be taken back. The
// screen hides what is pending straight away and the real delete runs when the time is up, when
// another delete arrives, or when the screen or the app goes away. Nothing is ever deleted and then
// rebuilt: an entry's cascade takes its insights, links, and loose ends, and rebuilding those
// faithfully is harder than never removing them.
@Observable
final class UndoQueue {
    struct Pending {
        let ids: Set<UUID>
        let message: String
        let commit: () -> Void
    }

    static let window: Duration = .seconds(5)

    private(set) var pending: Pending?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let window: Duration

    init(window: Duration = UndoQueue.window) {
        self.window = window
    }

    var hiddenIDs: Set<UUID> { pending?.ids ?? [] }

    func schedule(_ ids: Set<UUID>, message: String, commit: @escaping () -> Void) {
        commitNow()
        pending = Pending(ids: ids, message: message, commit: commit)
        let window = window
        timer = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.commitNow()
        }
    }

    func undo() {
        timer?.cancel()
        timer = nil
        pending = nil
    }

    func commitNow() {
        timer?.cancel()
        timer = nil
        guard let pending else { return }
        self.pending = nil
        pending.commit()
    }
}

extension View {
    // The pill along the bottom edge, and the commits that must not wait for the timer.
    func undoPill(_ queue: UndoQueue) -> some View {
        modifier(UndoPillModifier(queue: queue))
    }
}

private struct UndoPillModifier: ViewModifier {
    let queue: UndoQueue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let pending = queue.pending {
                    HStack(spacing: 16) {
                        Text(pending.message)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        Button("Undo") { queue.undo() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ember)
                            .accessibilityIdentifier("undoButton")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("undoPill")
                }
            }
            .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: queue.pending?.ids)
            .onChange(of: scenePhase) { _, phase in
                // RootView flushes the saver when the scene leaves active; a pending delete joins it.
                if phase != .active { queue.commitNow() }
            }
            .onDisappear { queue.commitNow() }
    }
}
