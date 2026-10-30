import SwiftUI
import UIKit

extension Notification.Name {
    static let tourOpenReader = Notification.Name("tourOpenReader")
    static let tourCloseReader = Notification.Name("tourCloseReader")
    static let tourShowMenu = Notification.Name("tourShowMenu")
    static let tourReaderSettings = Notification.Name("tourReaderSettings")
    static let tourDownloadSheet = Notification.Name("tourDownloadSheet")
}

/// Used only by the preview build: walks through the main screens and saves a screenshot of each
/// into the app's Documents/tour folder. Turned on with the -demoTour YES launch argument.
enum DemoTour {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "demoTour") }

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tour", isDirectory: true)
    }

    @MainActor
    static func snap(_ name: String) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
    }

    static func finish() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("done".utf8).write(to: folder.appendingPathComponent("done.txt"))
    }
}
