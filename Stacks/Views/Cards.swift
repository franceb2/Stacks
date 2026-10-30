import SwiftUI

/// Cover image that falls back to a local file (for downloads) and then a placeholder.
struct CoverImage: View {
    let url: URL?
    var localFile: URL? = nil

    var body: some View {
        Group {
            if let localFile, let image = UIImage(contentsOfFile: localFile.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                CachedImage(url: url) {
                    Rectangle().fill(Theme.card)
                        .overlay(Image(systemName: "book.closed").foregroundStyle(Theme.muted))
                }
                .aspectRatio(contentMode: .fill)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipped()
    }
}

/// Kavita's card: cover, green progress bar along the bottom edge, green triangle in the corner when unread.
struct KavitaCard: View {
    let title: String
    var subtitle: String? = nil
    let coverURL: URL?
    var localCover: URL? = nil
    var progress: Double = 0
    var unread = false
    var badge: String? = nil
    var downloaded: DownloadBadge? = nil
    /// nil when not selecting; true/false shows a check circle.
    var selected: Bool? = nil

    enum DownloadBadge { case full, partial, downloading(Double) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: coverURL, localFile: localCover)
                .overlay(alignment: .bottom) {
                    if progress > 0 && progress < 1 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.5))
                                Rectangle().fill(Theme.primary).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if unread {
                        Rectangle()
                            .fill(Theme.primary)
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(45))
                            .offset(x: 15, y: -15)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.primary, in: Capsule())
                            .padding(5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let downloaded { downloadIcon(downloaded).padding(6).padding(.bottom, 4) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if progress >= 1 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.4))
                            Image(systemName: "eye.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }
                        .accessibilityLabel("Read")
                    }
                }
                .overlay {
                    if let selected {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.black.opacity(selected ? 0 : 0.4))
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(selected ? Theme.primary : Color.clear, lineWidth: 3)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(selected ? Theme.onPrimary : Color.white,
                                                 selected ? Theme.primary : Color.black.opacity(0.4))
                                .padding(6)
                        }
                    }
                }

            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func downloadIcon(_ state: DownloadBadge) -> some View {
        switch state {
        case .full:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.onPrimary, Theme.primary)
        case .partial:
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.primary)
                .background(Circle().fill(Color.black.opacity(0.6)))
        case .downloading(let value):
            ZStack {
                Circle().fill(Color.black.opacity(0.6))
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.03, value))
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        }
    }
}

extension Downloads {
    func badge(for chapterId: Int) -> KavitaCard.DownloadBadge? {
        if let job = jobs[chapterId] { return .downloading(job.fraction) }
        guard let item = items[chapterId], !item.pages.isEmpty else { return nil }
        return item.isComplete ? .full : .partial
    }

    func badge(forChapters ids: [Int]) -> KavitaCard.DownloadBadge? {
        guard !ids.isEmpty else { return nil }
        if ids.contains(where: { jobs[$0] != nil }) {
            let done = ids.compactMap { jobs[$0]?.fraction }.reduce(0, +)
            return .downloading(done / Double(ids.count))
        }
        let states = ids.map { items[$0] }
        if states.allSatisfy({ $0?.isComplete == true }) { return .full }
        if states.contains(where: { !($0?.pages.isEmpty ?? true) }) { return .partial }
        return nil
    }
}

/// Grid layout used for every card list, like Kavita's card grid.
struct CardGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 14, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18, content: content)
            .padding(.horizontal, 16)
    }
}

/// A Kavita-style series card for grids and carousels.
struct SeriesCard: View {
    let series: Series
    let client: KavitaClient

    var body: some View {
        KavitaCard(title: series.name,
                   subtitle: series.libraryName,
                   coverURL: client.seriesCoverURL(series.id),
                   progress: series.progress,
                   unread: series.isUnread)
    }
}
