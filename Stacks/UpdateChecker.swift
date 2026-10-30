import Foundation
import SwiftUI

/// Checks GitHub for a newer Stacks build. iPhone doesn't let a sideloaded app install its own
/// updates, so this offers the download; Signulous does the install.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "franceb2/Stacks"
    static let downloadURL = URL(string: "https://github.com/\(repo)/releases/latest/download/Stacks.ipa")!

    struct Release: Equatable {
        let build: Int
        let name: String
        let notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var problem: String?

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
    }

    var installedBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var dismissedBuild: Int {
        get { UserDefaults.standard.integer(forKey: "dismissedUpdateBuild") }
        set { UserDefaults.standard.set(newValue, forKey: "dismissedUpdateBuild") }
    }

    /// True when there's a newer build the alert hasn't been dismissed for.
    var shouldAlert: Bool {
        guard let available else { return false }
        return available.build != dismissedBuild
    }

    func dismissAlert() {
        if let available { dismissedBuild = available.build }
        objectWillChange.send()
    }

    /// Checks at most once an hour unless `force` is set.
    func check(force: Bool = false) async {
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 3600 { return }
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                problem = "Couldn't check right now."
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let build = Int(release.tag_name.replacingOccurrences(of: "build-", with: "")) ?? 0
            lastChecked = Date()
            problem = nil
            available = build > installedBuild
                ? Release(build: build, name: release.name ?? "Stacks build \(build)", notes: release.body ?? "")
                : nil
        } catch {
            problem = "Couldn't check right now."
        }
    }
}
