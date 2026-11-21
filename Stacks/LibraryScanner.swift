import SwiftUI

/// Starts a Kavita library scan from the phone, so files you just added on the PC show up,
/// then refreshes the app a couple of times while Kavita works through them.
@MainActor
final class LibraryScanner: ObservableObject {
    static let shared = LibraryScanner()

    @Published private(set) var scanning = false
    @Published private(set) var message: String?
    @Published private(set) var failed = false

    private var job: Task<Void, Never>?

    /// nil scans every library.
    func scan(client: KavitaClient, library: Library?) {
        guard !scanning else { return }
        job?.cancel()
        scanning = true
        failed = false
        let name = library?.name ?? "all libraries"
        message = "Asking Kavita to scan \(name)…"
        job = Task {
            do {
                if let library { try await client.scanLibrary(library.id) } else { try await client.scanAllLibraries() }
            } catch {
                failed = true
                scanning = false
                message = Self.explain(error)
                return
            }
            message = "Kavita is scanning \(name). New comics will show up here in a moment."
            // Kavita scans in the background and doesn't say when it's done, so refresh a few times.
            for delay in [6, 15, 30] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                if Task.isCancelled { return }
                ReadingOrderStore.shared.invalidateLibrary()
                NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
            }
            scanning = false
            message = "Scan of \(name) requested. If something's still missing, pull down to refresh in a minute."
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled && !scanning { message = nil }
        }
    }

    func dismiss() {
        if !scanning { message = nil }
    }

    private static func explain(_ error: Error) -> String {
        if case KavitaError.http(let code, _) = error, code == 401 || code == 403 {
            return "Kavita only lets admin accounts start a scan. Sign in with your admin account, or turn on Folder Watching in Kavita's settings."
        }
        if let problem = ServerProblem.from(error) {
            return "Couldn't start the scan. \(problem.title). \(problem.detail)"
        }
        return "Couldn't start the scan. \(error.localizedDescription)"
    }
}

/// A small status card shown while a scan runs (and briefly after).
struct ScanBanner: View {
    @ObservedObject var scanner = LibraryScanner.shared

    var body: some View {
        if let message = scanner.message {
            HStack(alignment: .top, spacing: 10) {
                if scanner.scanning {
                    ProgressView().tint(Theme.primary)
                } else {
                    Image(systemName: scanner.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(scanner.failed ? Theme.danger : Theme.primary)
                }
                Text(message).font(.footnote).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !scanner.scanning {
                    Button {
                        scanner.dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
        }
    }
}
