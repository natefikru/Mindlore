import SwiftUI
import UIKit

// The + in the middle of the tab bar and the half circle of ways to start an entry that pops out of
// it (owner, 2026-09-24). The system tab bar only reports that a tab was picked, never a press, a
// slide, or a release, so the + is drawn here, over the bar's own + slot, with one gesture that does
// both: touch and let go to open the fan and tap an option, or touch, slide onto an option, and let
// go. The tab underneath stays for VoiceOver, which opens the fan through `AppRouter.select`.
struct NewEntryFan: View {
    @Environment(AppRouter.self) private var router
    @Environment(RecordingSession.self) private var recording
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The tab bar's frame in the window, read from UIKit by `TabBarProbe`.
    @State private var barFrame: CGRect = .zero
    // The option under the finger while a touch slides.
    @State private var hovered: NewEntryFanLayout.Option?
    // Per touch: whether it opened the fan, and whether it has left the +.
    @State private var touch: Touch?

    private struct Touch {
        let openedFan: Bool
        var leftPlus = false
    }

    private var isOpen: Bool { router.showingNewEntryFan }

    private var options: [NewEntryFanLayout.Option] {
        NewEntryFanLayout.options(pagesAvailable: DocumentCameraView.isSupported || FakePages.isEnabled)
    }

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            // The + slot is the middle of five, so it is the bar's centre whatever width each slot
            // gets. In this view's own space.
            let plus = CGPoint(x: barFrame.midX - origin.x, y: barFrame.midY - origin.y)
            let centers = NewEntryFanLayout.centers(around: plus, options: options)
            ZStack(alignment: .topLeading) {
                if isOpen {
                    backdrop
                        .transition(.opacity)
                }
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    if isOpen, let center = centers[option] {
                        // Offset, not `.position`: position stretches the button's frame over the
                        // whole screen, and a tap aimed at its middle landed on the backdrop.
                        optionButton(option)
                            .fixedSize()
                            .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - center.x }
                            .alignmentGuide(.top) { $0[VerticalAlignment.center] - center.y }
                            .transition(.popOut(from: CGPoint(x: plus.x - center.x, y: plus.y - center.y), reduceMotion: reduceMotion))
                            .animation(animation(delay: Double(index) * Motion.stagger), value: isOpen)
                    }
                }
                if barFrame != .zero, !router.editorHasKeyboard {
                    plusButton
                        .position(plus)
                        .gesture(drag(plus: plus, space: geometry.frame(in: .global).origin))
                }
            }
            .animation(animation(), value: isOpen)
        }
        .ignoresSafeArea()
        .background(TabBarProbe(frame: $barFrame).allowsHitTesting(false))
        .sensoryFeedback(Haptics.detent, trigger: hovered) { _, new in new != nil }
        .sensoryFeedback(Haptics.selected, trigger: isOpen)
    }

    private func animation(delay: Double = 0) -> Animation? {
        Motion.resolve(Motion.bloom, reduceMotion: reduceMotion).map { $0.delay(isOpen ? delay : 0) }
    }

    // Dims whatever is behind and takes any tap outside the options as a close.
    private var backdrop: some View {
        Rectangle()
            .fill(.black.opacity(0.22))
            .background(.ultraThinMaterial.opacity(0.6))
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("newEntryFanBackdrop")
    }

    private var plusButton: some View {
        ZStack {
            Circle()
                .fill(Palette.ember.gradient)
                .shadow(color: Palette.ember.opacity(isOpen ? 0.2 : 0.35), radius: isOpen ? 4 : 10, y: isOpen ? 1 : 4)
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
        }
        .frame(width: 54, height: 54)
        .scaleEffect(touch != nil ? 0.92 : 1)
        .animation(Motion.resolve(Motion.carry, reduceMotion: reduceMotion), value: touch != nil)
        // The whole slot takes the touch, not just the circle.
        .frame(width: 76, height: 64)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .accessibilityIdentifier("newEntryPlus")
    }

    private func optionButton(_ option: NewEntryFanLayout.Option) -> some View {
        let lifted = hovered == option
        return Button {
            choose(option, by: "tap")
        } label: {
            Image(systemName: optionSymbol(option))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(option == .record ? Color.white : Palette.ink)
                    .frame(width: NewEntryFanLayout.optionDiameter, height: NewEntryFanLayout.optionDiameter)
                    // Glass takes no touches of its own: without this only the glyph was tappable.
                    .contentShape(Circle())
                    .background {
                        if option == .record {
                            Circle().fill(Palette.ember.gradient)
                        }
                    }
                    .glassEffect(option == .record ? .regular.tint(Palette.ember) : .regular.interactive(), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    // Hangs under the circle rather than stacking with it, so the button's frame
                    // is the circle and its centre is the option's place on the arc.
                    .overlay(alignment: .bottom) {
                        Text(optionTitle(option))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 3)
                            .fixedSize()
                            .offset(y: 22)
                    }
            .scaleEffect(lifted ? 1.14 : 1)
            .animation(Motion.resolve(Motion.carry, reduceMotion: reduceMotion), value: lifted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(optionTitle(option))
        .accessibilityIdentifier("newEntryFan-\(option.rawValue)")
    }

    // While a recording runs, Record brings it back rather than starting a second one.
    private func optionTitle(_ option: NewEntryFanLayout.Option) -> String {
        option == .record && recording.status != .idle ? "Recording" : option.title
    }

    private func optionSymbol(_ option: NewEntryFanLayout.Option) -> String {
        option == .record && recording.status != .idle ? "waveform" : option.symbol
    }

    // One gesture for the tap and the slide. The fan opens on touch-down; release decides.
    private func drag(plus: CGPoint, space: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let point = CGPoint(x: value.location.x - space.x, y: value.location.y - space.y)
                if touch == nil {
                    touch = Touch(openedFan: !isOpen)
                    if !isOpen { router.showingNewEntryFan = true }
                }
                if NewEntryFanLayout.distance(point, plus) > NewEntryFanLayout.plusHitRadius {
                    touch?.leftPlus = true
                }
                hovered = isOpen ? NewEntryFanLayout.option(at: point, plus: plus, options: options) : nil
            }
            .onEnded { value in
                let point = CGPoint(x: value.location.x - space.x, y: value.location.y - space.y)
                let current = touch
                touch = nil
                hovered = nil
                // A jump (Siri, a notification) may have closed the fan under the finger.
                guard isOpen, let current else { return }
                switch NewEntryFanLayout.release(at: point, plus: plus, options: options, leftPlus: current.leftPlus, openedByThisTouch: current.openedFan) {
                case .choose(let option): choose(option, by: "slide")
                case .stayOpen: break
                case .close: close()
                }
            }
    }

    private func close() {
        router.showingNewEntryFan = false
    }

    private func choose(_ option: NewEntryFanLayout.Option, by gesture: String) {
        DiagnosticsLog.shared.record("newEntry.chosen", ["option": .string(option.rawValue), "by": .string(gesture)])
        close()
        switch option {
        case .write: router.showNewEntry()
        case .record: IntentHandler.handle(.record, recording: recording, router: router)
        case .pages: router.showNewPages()
        }
    }
}

// An option flies out of the + along the line to its place, growing as it goes, and folds back the
// same way. Opacity only under Reduce Motion.
private struct PopOutTransition: Transition {
    let offset: CGPoint
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let away = !phase.isIdentity && !reduceMotion
        content
            .scaleEffect(away ? 0.2 : 1)
            .offset(x: away ? offset.x : 0, y: away ? offset.y : 0)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

private extension Transition where Self == PopOutTransition {
    static func popOut(from offset: CGPoint, reduceMotion: Bool) -> PopOutTransition {
        PopOutTransition(offset: offset, reduceMotion: reduceMotion)
    }
}

// Reports the visible tab bar's frame in window coordinates. SwiftUI's TabView is a UITabBarController
// underneath, and its bar is the one thing that knows where the + slot is drawn.
private struct TabBarProbe: UIViewRepresentable {
    @Binding var frame: CGRect

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.report = { frame = $0 }
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.report = { frame = $0 }
        view.setNeedsLayout()
    }

    final class ProbeView: UIView {
        var report: ((CGRect) -> Void)?
        private var last: CGRect = .zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measure()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        private func measure() {
            guard let window, let bar = Self.tabBar(in: window), !bar.isHidden else { return }
            // The visible bar, without the home indicator's strip the bar also covers.
            var frame = bar.convert(bar.bounds, to: window)
            frame.size.height -= bar.safeAreaInsets.bottom
            guard frame != last else { return }
            last = frame
            DispatchQueue.main.async { [report] in report?(frame) }
        }

        private static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for subview in view.subviews {
                if let bar = tabBar(in: subview) { return bar }
            }
            return nil
        }
    }
}
