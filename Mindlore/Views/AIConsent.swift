import SwiftUI

// The one question asked before anything from the journal goes to OpenAI (App Review guideline
// 5.1.2(i): name the third-party AI, say what it gets, and get explicit permission first).
// `aiEnabled` is the gate every OpenAI path checks, so the only ways to turn it on from the app are
// the Use AI switch and saving a key, and both go through this alert. Turning AI off never asks.
enum AIConsent {
    static let title = "Send your journal to OpenAI?"
    static let message = "With AI on, Mindlore sends your recordings, photos of journal pages, and the text of your entries to OpenAI, using your own key, to write text, titles, and insights. A question in Chat sends the entries it needs. OpenAI's terms cover what happens to them there. You can turn AI off at any time."
    static let allow = "Allow"
    static let notNow = "Not now"
    static let keyURL = URL(string: "https://platform.openai.com/api-keys")!
}

private struct AIConsentModifier: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(AIConsent.title, isPresented: $isPresented) {
            Button(AIConsent.notNow, role: .cancel) { record(allowed: false) }
                .accessibilityIdentifier("aiConsentNotNow")
            Button(AIConsent.allow) {
                settings.aiEnabled = true
                record(allowed: true)
            }
            .accessibilityIdentifier("aiConsentAllow")
        } message: {
            Text(AIConsent.message)
        }
    }

    private func record(allowed: Bool) {
        DiagnosticsLog.shared.record("ai.consent", ["allowed": .bool(allowed)])
    }
}

extension View {
    // Asks, and turns AI on only on Allow.
    func aiConsent(isPresented: Binding<Bool>) -> some View {
        modifier(AIConsentModifier(isPresented: isPresented))
    }
}
