import SwiftUI
import UIKit

// MARK: - Finding panels

/// Finds comic panels on a page by looking for the gutters (the plain white or black strips between panels),
/// then cutting the page along them: rows top to bottom, panels across each row (right to left for manga).
/// Runs on the phone; nothing is sent anywhere. Returns rects from 0 to 1, or [] when the page has no clear
/// panels (splash pages, borderless art), in which case the whole page is shown.
enum PanelDetector {
    static func panels(in image: UIImage, rightToLeft: Bool) -> [CGRect] {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return [] }
        let maxSide = 520.0
        let scale = min(1, maxSide / Double(max(cg.width, cg.height)))
        let w = max(Int(Double(cg.width) * scale), 1)
        let h = max(Int(Double(cg.height) * scale), 1)
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }

        // The gutter color is whatever the page's outer edge mostly is.
        var edge: [UInt8] = []
        for x in 0..<w { edge.append(pixels[x]); edge.append(pixels[(h - 1) * w + x]) }
        for y in 0..<h { edge.append(pixels[y * w]); edge.append(pixels[y * w + w - 1]) }
        edge.sort()
        let background = Int(edge[edge.count / 2])
        // Only white-ish or black-ish edges make reliable gutters.
        guard background > 200 || background < 55 else { return [] }
        let gutter = pixels.map { abs(Int($0) - background) <= 38 }

        struct Box { var x0, y0, x1, y1: Int }   // end exclusive

        func fraction(row y: Int, _ b: Box) -> Double {
            var n = 0
            for x in b.x0..<b.x1 where gutter[y * w + x] { n += 1 }
            return Double(n) / Double(max(b.x1 - b.x0, 1))
        }
        func fraction(column x: Int, _ b: Box) -> Double {
            var n = 0
            for y in b.y0..<b.y1 where gutter[y * w + x] { n += 1 }
            return Double(n) / Double(max(b.y1 - b.y0, 1))
        }
        let solid = 0.97

        func trim(_ b: Box) -> Box? {
            var b = b
            while b.y0 < b.y1, fraction(row: b.y0, b) >= solid { b.y0 += 1 }
            while b.y1 > b.y0, fraction(row: b.y1 - 1, b) >= solid { b.y1 -= 1 }
            while b.x0 < b.x1, fraction(column: b.x0, b) >= solid { b.x0 += 1 }
            while b.x1 > b.x0, fraction(column: b.x1 - 1, b) >= solid { b.x1 -= 1 }
            return (b.x1 - b.x0 > 2 && b.y1 - b.y0 > 2) ? b : nil
        }

        /// Pieces of `b` separated by gutters running across it (rows) or down it (columns).
        func split(_ b: Box, rows: Bool) -> [Box] {
            let length = rows ? b.y1 - b.y0 : b.x1 - b.x0
            let minGap = max(2, Int(Double(rows ? h : w) * 0.006))
            var pieces: [Box] = []
            var start: Int?
            var gap = 0
            for i in 0..<length {
                let line = rows ? b.y0 + i : b.x0 + i
                let isGutter = rows ? fraction(row: line, b) >= solid : fraction(column: line, b) >= solid
                if isGutter {
                    gap += 1
                    if let s = start, gap >= minGap {
                        let end = line - gap + 1
                        pieces.append(rows ? Box(x0: b.x0, y0: s, x1: b.x1, y1: end) : Box(x0: s, y0: b.y0, x1: end, y1: b.y1))
                        start = nil
                    }
                } else {
                    if start == nil { start = line }
                    gap = 0
                }
            }
            if let s = start {
                let end = (rows ? b.y1 : b.x1) - gap
                pieces.append(rows ? Box(x0: b.x0, y0: s, x1: b.x1, y1: end) : Box(x0: s, y0: b.y0, x1: end, y1: b.y1))
            }
            return pieces
        }

        func cut(_ box: Box, depth: Int) -> [Box] {
            guard let b = trim(box) else { return [] }
            if depth > 6 { return [b] }
            let rowPieces = split(b, rows: true)
            if rowPieces.count > 1 { return rowPieces.flatMap { cut($0, depth: depth + 1) } }
            let columnPieces = split(b, rows: false)
            if columnPieces.count > 1 {
                return (rightToLeft ? columnPieces.reversed() : columnPieces).flatMap { cut($0, depth: depth + 1) }
            }
            return [b]
        }

        let pageArea = Double(w * h)
        let found = cut(Box(x0: 0, y0: 0, x1: w, y1: h), depth: 0).filter { b in
            // Drop specks like page numbers and stray captions.
            let bw = Double(b.x1 - b.x0), bh = Double(b.y1 - b.y0)
            return bw * bh >= pageArea * 0.015 && bw >= Double(w) * 0.06 && bh >= Double(h) * 0.04
        }
        guard found.count > 1 else { return [] }

        let pad = 0.008
        return found.map { b in
            let x0 = max(0, Double(b.x0) / Double(w) - pad), y0 = max(0, Double(b.y0) / Double(h) - pad)
            let x1 = min(1, Double(b.x1) / Double(w) + pad), y1 = min(1, Double(b.y1) / Double(h) + pad)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}

/// Panels found for each page, kept on the phone so a page is only examined once (works offline too).
@MainActor
enum PanelCache {
    private static var memory: [Int: [String: [[Double]]]] = [:]

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Panels", isDirectory: true)
    }

    private static func key(_ page: Int, _ rightToLeft: Bool) -> String { "v1-\(page)-\(rightToLeft ? "r" : "l")" }

    private static func load(_ chapterId: Int) -> [String: [[Double]]] {
        if let hit = memory[chapterId] { return hit }
        let file = folder.appendingPathComponent("\(chapterId).json")
        let saved = (try? JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: file))) ?? [:]
        memory[chapterId] = saved
        return saved
    }

    static func get(chapterId: Int, page: Int, rightToLeft: Bool) -> [CGRect]? {
        load(chapterId)[key(page, rightToLeft)].map { list in
            list.compactMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        }
    }

    static func set(_ rects: [CGRect], chapterId: Int, page: Int, rightToLeft: Bool) {
        var all = load(chapterId)
        all[key(page, rightToLeft)] = rects.map { [$0.minX, $0.minY, $0.width, $0.height] }
        memory[chapterId] = all
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: folder.appendingPathComponent("\(chapterId).json"), options: .atomic)
    }
}

// MARK: - Guided reading

/// Panel-by-panel reading: zooms to one panel at a time and dims the rest of the page.
/// Tap the side (or swipe) for the next or previous panel; after the last panel it moves to the next page.
struct PanelPager: View {
    @ObservedObject var store: PageImageStore
    let chapterId: Int
    let pageCount: Int
    @Binding var page: Int
    let rightToLeft: Bool
    let offline: Bool
    let tapToTurn: Bool
    let background: Color
    let actions: ReaderActions
    let toggleChrome: () -> Void

    @State private var panels: [Int: [CGRect]] = [:]
    /// Int.max means "the last panel" (used when going back a page).
    @State private var panelIndex = 0

    private static let wholePage = CGRect(x: 0, y: 0, width: 1, height: 1)

    private func list(_ page: Int) -> [CGRect] {
        let found = panels[page] ?? []
        return found.isEmpty ? [Self.wholePage] : found
    }

    private var current: CGRect {
        let l = list(page)
        return l[min(max(panelIndex, 0), l.count - 1)]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if page >= pageCount {
                    EndOfChapterView(actions: actions)
                } else if let image = store.images[page] {
                    panelImage(image, in: geo.size)
                } else if store.failed.contains(page) {
                    PageProblem(index: page, offline: offline) { store.load(page, force: true) }
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard page < pageCount else { return }
                tap(geo.size.width > 0 ? location.x / geo.size.width : 0.5)
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard page < pageCount, abs(value.translation.width) > abs(value.translation.height) else { return }
                    let leftSwipe = value.translation.width < 0
                    // Swiping left moves forward in comics, back in manga.
                    move(forward: rightToLeft ? !leftSwipe : leftSwipe)
                }
            )
        }
        .background(background)
        .ignoresSafeArea()
        .task(id: "\(page)-\(store.images[page] != nil)") { await detect(page) }
        .onAppear { store.load(page) }
    }

    @ViewBuilder
    private func panelImage(_ image: UIImage, in screen: CGSize) -> some View {
        let rect = current
        let imageSize = image.size
        let panelW = max(rect.width * imageSize.width, 1)
        let panelH = max(rect.height * imageSize.height, 1)
        let margin: CGFloat = rect == Self.wholePage ? 1 : 0.96
        let scale = min(screen.width * margin / panelW, screen.height * margin / panelH)
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let center = CGPoint(x: screen.width / 2 - (rect.midX * shown.width - shown.width / 2),
                             y: screen.height / 2 - (rect.midY * shown.height - shown.height / 2))
        let hole = CGRect(x: screen.width / 2 - panelW * scale / 2, y: screen.height / 2 - panelH * scale / 2,
                          width: panelW * scale, height: panelH * scale)

        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: shown.width, height: shown.height)
                .position(center)
            if rect != Self.wholePage {
                // Dim everything but the current panel.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: screen))
                    p.addRect(hole)
                }
                .fill(background.opacity(0.92), style: FillStyle(eoFill: true))
            }
        }
        .frame(width: screen.width, height: screen.height)
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: rect)
    }

    private func tap(_ x: CGFloat) {
        if !tapToTurn || (x > 0.3 && x < 0.7) {
            toggleChrome()
            return
        }
        let leftSide = x <= 0.3
        move(forward: rightToLeft ? leftSide : !leftSide)
    }

    private func move(forward: Bool) {
        let count = list(page).count
        let index = min(max(panelIndex, 0), count - 1)
        withAnimation(.easeInOut(duration: 0.35)) {
            if forward {
                if index + 1 < count {
                    panelIndex = index + 1
                } else {
                    panelIndex = 0
                    page = min(page + 1, pageCount)
                }
            } else {
                if index > 0 {
                    panelIndex = index - 1
                } else if page > 0 {
                    panelIndex = Int.max   // last panel of the previous page
                    page -= 1
                }
            }
        }
    }

    private func detect(_ index: Int) async {
        guard index < pageCount, panels[index] == nil else { return }
        if let saved = PanelCache.get(chapterId: chapterId, page: index, rightToLeft: rightToLeft) {
            panels[index] = saved
            return
        }
        guard let image = store.images[index] else { return }
        let rtl = rightToLeft
        let found = await Task.detached(priority: .userInitiated) {
            PanelDetector.panels(in: image, rightToLeft: rtl)
        }.value
        panels[index] = found
        PanelCache.set(found, chapterId: chapterId, page: index, rightToLeft: rtl)
    }
}
