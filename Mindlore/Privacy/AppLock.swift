import LocalAuthentication
import Observation
import SwiftUI
import UIKit

// Face ID (or the passcode) in front of the journal, off unless the user turns it on. The app locks
// whenever it goes to the background and asks again when it comes back; a recording keeps running
// underneath. The cover is its own window above everything else, because an overlay on the tab
// view sits under the editor, the recorder, and every sheet, which is where a journal is open.
//
// The cover also goes up while the app is merely inactive, so the app switcher's snapshot shows it
// rather than whatever entry was on screen.
@Observable
final class AppLock {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    // The last unlock was refused or cancelled, so the cover offers a button instead of asking again
    // straight away, which would loop.
    private(set) var lastAttemptFailed = false

    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let authenticate: (String) async -> Bool
    @ObservationIgnored private let cover: (Bool) -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog

    static let reason = "Unlock your journal"

    init(
        isEnabled: @escaping () -> Bool,
        authenticate: @escaping (String) async -> Bool = AppLock.systemAuthenticate,
        cover: ((Bool) -> Void)? = nil,
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.isEnabled = isEnabled
        self.authenticate = authenticate
        self.diagnostics = diagnostics
        self.cover = cover ?? { _ in }
        if cover == nil {
            let window = LockWindow()
            self.coverWindow = window
        }
    }

    @ObservationIgnored private var coverWindow: LockWindow?

    private func setCover(_ shown: Bool) {
        if let coverWindow {
            shown ? coverWindow.show(for: self) : coverWindow.hide()
        } else {
            cover(shown)
        }
    }

    // At launch, before the first frame of the journal is drawn.
    func lockAtLaunch() {
        guard isEnabled() else { return }
        isLocked = true
        setCover(true)
    }

    func sceneChanged(to phase: ScenePhase) {
        guard isEnabled() else {
            if isLocked || coverWindow?.isShowing == true {
                isLocked = false
                setCover(false)
            }
            return
        }
        switch phase {
        case .background:
            if !isLocked { diagnostics.record("lock.locked", [:]) }
            isLocked = true
            lastAttemptFailed = false
            setCover(true)
        case .inactive:
            // The Face ID sheet itself makes the scene inactive; the cover is already up for it.
            setCover(true)
        case .active:
            if isLocked {
                if !lastAttemptFailed { Task { await unlock() } }
            } else {
                setCover(false)
            }
        @unknown default:
            break
        }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let allowed = await authenticate(Self.reason)
        isAuthenticating = false
        lastAttemptFailed = !allowed
        diagnostics.record("lock.unlock", ["ok": .bool(allowed)])
        guard allowed else { return }
        isLocked = false
        setCover(false)
    }

    // Turning the setting off from inside the app: nothing to hide behind any more.
    func disabled() {
        isLocked = false
        lastAttemptFailed = false
        setCover(false)
    }

    // Face ID, Touch ID, or the passcode when neither is set up or both fail.
    nonisolated static func systemAuthenticate(_ reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // A phone with no passcode can't be locked by anything, so the setting can't be turned on.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Passcode"
        }
    }
}

// Never the key window: a cover that took key status could take the keyboard from the entry being
// written, and nothing would give it back when the cover went. Taps still reach its Unlock button.
private final class CoverWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

// The window the cover lives in, above alerts, so nothing the app presents can sit on top of it.
private final class LockWindow {
    private var window: UIWindow?

    var isShowing: Bool { window?.isHidden == false }

    func show(for lock: AppLock) {
        if let window {
            window.isHidden = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = CoverWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = AppearancePreference.appliedStyle
        let host = UIHostingController(rootView: LockCoverView(lock: lock))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
    }
}

struct LockCoverView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.ember)
                .accessibilityHidden(true)
            Text("Mindlore is locked")
                .font(.title3.weight(.semibold))
            if lock.isLocked && !lock.isAuthenticating {
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ember)
                    .accessibilityIdentifier("unlockButton")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
        .accessibilityIdentifier("lockCover")
    }
}
