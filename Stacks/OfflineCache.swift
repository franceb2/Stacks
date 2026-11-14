import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Why the server can't be reached, in plain words.
enum ServerProblem: Equatable {
    case phoneOffline      // no internet on the phone
    case tunnelDown        // Cloudflare can't reach the PC (error 1033 / HTTP 530)
    case kavitaDown        // tunnel is fine but Kavita isn't answering (HTTP 502/504)
    case unreachable       // server address can't be reached (home address while away, PC off, etc.)

    var title: String {
        switch self {
        case .phoneOffline: return "Your phone is offline"
        case .tunnelDown: return "Your PC or its tunnel is offline"
        case .kavitaDown: return "Kavita isn't running on your PC"
        case .unreachable: return "Can't reach your server"
        }
    }

    var detail: String {
        switch self {
        case .phoneOffline:
            return "Connect to Wi-Fi or cellular. Downloads still open."
        case .tunnelDown:
            return "Cloudflare can't reach your PC (error 1033). Make sure the PC is on and awake, and the Cloudflared service is running."
        case .kavitaDown:
            return "Your PC is reachable, but Kavita isn't answering (error 502). Start Kavita, or its service, on the PC."
        case .unreachable:
            return "Check that the PC is on and the server address is right."
        }
    }

    static func from(_ error: Error) -> ServerProblem? {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return nil
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .phoneOffline
            default: return .unreachable
            }
        }
        if case KavitaError.http(let code, let body) = error {
            if code == 530 || body.contains("1033") { return .tunnelDown }
            if code == 502 || code == 504 { return .kavitaDown }
            if code == 503 { return .unreachable }
        }
        return nil
    }
}

/// Whether the app is currently showing saved data because the server can't be reached, and why.
@MainActor
final class ConnectionStatus: ObservableObject {
    static let shared = ConnectionStatus()
    @Published private(set) var problem: ServerProblem?
    var offline: Bool { problem != nil }

    nonisolated static func report(offline: Bool) {
        guard !offline else { return }
        Task { @MainActor in
            if shared.problem != nil { shared.problem = nil }
        }
    }

    nonisolated static func report(_ problem: ServerProblem) {
        Task { @MainActor in
            if shared.problem != problem { shared.problem = problem }
        }
    }
}

extension Notification.Name {
    /// Posted when the phone's network connection comes back.
    static let networkReturned = Notification.Name("networkReturned")
}

/// Saved copies of what the server last sent (libraries, series lists, series pages, lists...),
/// so browsing still works with no connection.
enum ResponseCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("api", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func key(method: String, path: String, query: [String: String], body: Data?) -> String {
        let q = query.filter { $0.key != "apiKey" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        var input = Data("\(method) \(path)?\(q)".utf8)
        if let body { input.append(body) }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func store(_ data: Data, key: String) {
        try? data.write(to: dir.appendingPathComponent(key), options: .atomic)
    }

    static func load(key: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(key))
    }
}

/// Cover images kept on the phone so the library looks the same offline.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL

    private init() {
        memory.countLimit = 400
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Same picture regardless of which Auth Key is in the address.
    private func key(_ url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems?.filter { $0.name != "apiKey" }.sorted { $0.name < $1.name }
        comps?.queryItems = items
        let text = comps?.string ?? url.absoluteString
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: key(url) as NSString)
    }

    /// Shows the saved copy right away; refreshes it from the server when it's a few days old.
    func image(for url: URL) async -> UIImage? {
        let k = key(url)
        if let hit = memory.object(forKey: k as NSString) { return hit }
        let file = dir.appendingPathComponent(k)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            let decoded = img.preparingForDisplay() ?? img
            memory.setObject(decoded, forKey: k as NSString)
            let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { Date().timeIntervalSince($0) } ?? 0
            if age > 3 * 86_400 { Task.detached { await self.refresh(url, key: k, file: file) } }
            return decoded
        }
        return await refresh(url, key: k, file: file)
    }

    /// Saves a cover to disk if it isn't there yet (no decoding, used for background saving).
    func warm(_ url: URL?) async {
        guard let url else { return }
        let file = dir.appendingPathComponent(key(url))
        if FileManager.default.fileExists(atPath: file.path) { return }
        var req = URLRequest(url: url)
        req.setValue(KavitaClient.clientHeader, forHTTPHeaderField: "X-Kavita-Client")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 64 else { return }
        try? data.write(to: file, options: .atomic)
    }

    @discardableResult
    private func refresh(_ url: URL, key k: String, file: URL) async -> UIImage? {
        var req = URLRequest(url: url)
        req.setValue(KavitaClient.clientHeader, forHTTPHeaderField: "X-Kavita-Client")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        let decoded = img.preparingForDisplay() ?? img
        memory.setObject(decoded, forKey: k as NSString)
        return decoded
    }
}

/// An image that loads through the cover cache.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let loaded = await ImageCache.shared.image(for: url) {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
    }
}
