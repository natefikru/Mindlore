import SwiftUI

// The one screen a new install sees: what Mindlore is, what stays on the phone, and a way in.
// Deliberately not a tour or a questionnaire. Permissions are asked where they're needed (the
// microphone on the first recording), because that is when the reason is obvious.
struct WelcomeView: View {
    let onStart: () -> Void
    let onAddKey: () -> Void

    private let onDevice = FoundationModelsAvailability.isAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    // The identifier sits on the title, not the screen: on an ancestor it would
                    // overwrite the buttons' own.
                    Text("Mindlore")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityIdentifier("welcomeView")
                    Text("A journal that keeps track of what you write about.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 24) {
                    row("mic", "Speak or write", "Record an entry, type one, or photograph a page from a paper journal.")
                    row("circle.hexagongrid", "See how it connects", "The people, places, and open threads in your entries collect into a map you can search and correct.")
                    row("lock", "Stays on this iPhone", onDevice
                        ? "Entries are read by Apple's on-device model. Nothing leaves your phone unless you add an OpenAI key."
                        : "Nothing leaves your phone unless you add an OpenAI key, which also reads your entries for names, moods, and threads.")
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onStart) {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ember)
                .accessibilityIdentifier("welcomeStart")
                Button("I have an OpenAI key", action: onAddKey)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ember)
                    .accessibilityIdentifier("welcomeAddKey")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Palette.ember)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onStart: {}, onAddKey: {})
}
