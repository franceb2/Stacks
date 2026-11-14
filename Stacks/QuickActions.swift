import LocalAuthentication
import SwiftUI
import UIKit

/// Long-press the app icon → "Continue reading" jumps straight back into the last comic or book.
enum QuickActions {
    static let continueType = "continue-reading"

    static func setContinue(chapterId: Int, readingListId: Int?, seriesName: String, chapterTitle: String) {
        var info: [String: NSSecureCoding] = ["chapterId": NSNumber(value: chapterId)]
        if let readingListId { info["readingListId"] = NSNumber(value: readingListId) }
        let subtitle = [seriesName, chapterTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: continueType, localizedTitle: "Continue reading",
                                      localizedSubtitle: subtitle.isEmpty ? nil : subtitle,
                                      icon: UIApplicationShortcutIcon(systemImageName: "book.fill"),
                                      userInfo: info),
        ]
    }

    /// Chapter waiting to be opened from a shortcut.
    @MainActor static var pending: ReaderLaunch?

    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) {
        guard item.type == continueType,
              let id = (item.userInfo?["chapterId"] as? NSNumber)?.intValue else { return }
        let listId = (item.userInfo?["readingListId"] as? NSNumber)?.intValue
        pending = ReaderLaunch(chapterId: id, readingListId: listId)
        NotificationCenter.default.post(name: .openFromShortcut, object: nil)
    }
}

extension Notification.Name {
    static let openFromShortcut = Notification.Name("openFromShortcut")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            Task { @MainActor in QuickActions.handle(item) }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in QuickActions.handle(shortcutItem) }
        completionHandler(true)
    }
}

// MARK: - Face ID lock

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published private(set) var locked: Bool
    @Published private(set) var authenticating = false

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "faceIDLock") }
        set { UserDefaults.standard.set(newValue, forKey: "faceIDLock") }
    }

    private init() { locked = Self.enabled }

    /// Called when the app goes to the background: lock again for next time.
    func lockIfEnabled() {
        if Self.enabled { locked = true }
    }

    func unlock() {
        guard locked, !authenticating else { return }
        authenticating = true
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Stacks") { success, _ in
            Task { @MainActor in
                self.authenticating = false
                if success { self.locked = false }
            }
        }
    }

    /// Checks Face ID works before turning the lock on.
    func enable(_ on: Bool) async -> Bool {
        guard on else {
            Self.enabled = false
            locked = false
            return true
        }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Turn on Face ID lock for Stacks")) ?? false
        Self.enabled = ok
        return ok
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }
}

/// Covers the app until it's unlocked (also hides it in the app switcher).
struct LockScreen: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Theme.primary)
                Text("Stacks is locked").font(.title3.bold()).foregroundStyle(Theme.text)
                Button {
                    lock.unlock()
                } label: {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .onAppear { lock.unlock() }
    }
}
