import SwiftUI
import WebKit

/// EPUB reader. Kavita splits a book into sections (its "pages"); each section is shown as a
/// scrolling web page. Kavita tracks the section; the scroll spot inside it is kept on the phone.
struct EPUBReaderView: View {
    let context: ReaderContext
    let client: KavitaClient
    let actions: ReaderActions

    @AppStorage("epubFontSize") private var fontSize = 110.0
    @State private var section: Int
    @State private var html: String?
    @State private var toc: [BookTOCItem] = []
    @State private var error: String?
    @State private var restoreFraction: Double?
    @State private var jumpToPart: String?
    @State private var showEnd = false

    init(context: ReaderContext, client: KavitaClient, actions: ReaderActions) {
        self.context = context
        self.client = client
        self.actions = actions
        _section = State(initialValue: context.startPage)
        if let saved = LocalBookPosition.load(chapterId: context.chapterId), saved.section == context.startPage {
            _restoreFraction = State(initialValue: saved.fraction)
        }
    }

    private var sectionCount: Int { max(context.info.pages, 1) }

    var body: some View {
        NavigationStack {
            Group {
                if showEnd {
                    EndOfChapterView(actions: actions)
                } else if let html {
                    EPUBWebView(html: html, baseURL: client.baseURL, fontSize: fontSize,
                                restoreFraction: restoreFraction, jumpToPart: jumpToPart,
                                onScroll: scrolled, onInternalLink: followLink)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { Task { await loadSection() } }.buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .task { toc = (try? await client.bookTOC(chapterId: context.chapterId)) ?? [] }
        .task(id: section) { await loadSection() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { actions.close() } label: { Image(systemName: "xmark") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !toc.isEmpty {
                Menu {
                    ForEach(flatten(toc)) { entry in
                        Button(String(repeating: "   ", count: entry.depth) + (entry.item.title ?? "Section \(entry.item.page + 1)")) {
                            go(to: entry.item.page)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
            Menu {
                Button("Larger text", systemImage: "textformat.size.larger") { fontSize = min(fontSize + 10, 250) }
                Button("Smaller text", systemImage: "textformat.size.smaller") { fontSize = max(fontSize - 10, 60) }
                Button("Reset text size") { fontSize = 110 }
            } label: {
                Image(systemName: "textformat.size")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { go(to: section - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(section == 0 || showEnd)
            Spacer()
            Text(showEnd ? "Finished" : "Section \(section + 1) of \(sectionCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if section >= sectionCount - 1 {
                Button("Finish") { showEnd = true }
                    .disabled(showEnd)
            } else {
                Button { go(to: section + 1) } label: { Image(systemName: "chevron.right") }
            }
        }
    }

    private func go(to newSection: Int) {
        guard newSection >= 0, newSection < sectionCount else { return }
        showEnd = false
        restoreFraction = nil
        jumpToPart = nil
        section = newSection
    }

    private func loadSection() async {
        html = nil
        error = nil
        do {
            html = try await client.bookPageHTML(chapterId: context.chapterId, page: section)
            actions.pageChanged(section)
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scrolled(_ fraction: Double) {
        LocalBookPosition.save(chapterId: context.chapterId, section: section, fraction: fraction)
        if section >= sectionCount - 1 && fraction >= 0.97 {
            actions.finished()
        }
    }

    private func followLink(page: Int, part: String?) {
        if page == section {
            jumpToPart = part
        } else {
            go(to: page)
            jumpToPart = part
        }
    }

    private struct TOCEntry: Identifiable {
        let id: Int
        let item: BookTOCItem
        let depth: Int
    }

    private func flatten(_ items: [BookTOCItem]) -> [TOCEntry] {
        var out: [TOCEntry] = []
        func walk(_ list: [BookTOCItem], _ depth: Int) {
            for item in list {
                out.append(TOCEntry(id: out.count, item: item, depth: depth))
                walk(item.children ?? [], depth + 1)
            }
        }
        walk(items, 0)
        return out
    }
}

/// Scroll position inside the current section, kept on the phone.
enum LocalBookPosition {
    static func save(chapterId: Int, section: Int, fraction: Double) {
        UserDefaults.standard.set(["section": section, "fraction": fraction], forKey: "epub-pos-\(chapterId)")
    }

    static func load(chapterId: Int) -> (section: Int, fraction: Double)? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "epub-pos-\(chapterId)"),
              let section = dict["section"] as? Int,
              let fraction = dict["fraction"] as? Double else { return nil }
        return (section, fraction)
    }
}

// MARK: - Web view

struct EPUBWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL
    let fontSize: Double
    let restoreFraction: Double?
    let jumpToPart: String?
    let onScroll: (Double) -> Void
    let onInternalLink: (Int, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let proxy = WeakMessageHandler(context.coordinator)
        controller.add(proxy, name: "scroll")
        controller.add(proxy, name: "link")
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        context.coordinator.webView = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.loadedHTML != html {
            coordinator.loadedHTML = html
            coordinator.pendingFraction = restoreFraction
            coordinator.pendingPart = jumpToPart
            coordinator.appliedFontSize = fontSize
            web.loadHTMLString(Self.wrap(html, fontSize: fontSize), baseURL: baseURL)
        } else {
            if coordinator.appliedFontSize != fontSize {
                coordinator.appliedFontSize = fontSize
                web.evaluateJavaScript("document.body.style.fontSize='\(Int(fontSize))%'")
            }
            if let part = jumpToPart, part != coordinator.lastJumpedPart {
                coordinator.scroll(toPart: part)
            }
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        weak var webView: WKWebView?
        var loadedHTML: String?
        var pendingFraction: Double?
        var pendingPart: String?
        var lastJumpedPart: String?
        var appliedFontSize: Double = 0

        init(parent: EPUBWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let part = pendingPart {
                scroll(toPart: part)
            } else if let fraction = pendingFraction {
                webView.evaluateJavaScript(
                    "window.scrollTo(0, Math.max(0, document.documentElement.scrollHeight - window.innerHeight) * \(fraction)); stacksReport();")
            } else {
                webView.evaluateJavaScript("stacksReport();")
            }
            pendingFraction = nil
            pendingPart = nil
        }

        func scroll(toPart part: String) {
            lastJumpedPart = part
            let escaped = part.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript(
                "(function(){var el=document.getElementById('\(escaped)')||document.getElementsByName('\(escaped)')[0];if(el){el.scrollIntoView();}stacksReport();})();")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Links to the outside web open in Safari instead of replacing the book.
            if action.navigationType == .linkActivated, let url = action.request.url,
               let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme),
               url.fragment == nil || url.host != parent.baseURL.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "scroll":
                if let value = message.body as? Double { parent.onScroll(value) }
                else if let value = message.body as? Int { parent.onScroll(Double(value)) }
            case "link":
                guard let body = message.body as? [String: Any], let page = body["page"] as? Int else { return }
                let part = (body["part"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                parent.onInternalLink(page, part)
            default:
                break
            }
        }
    }

    /// Avoids a retain cycle between WKUserContentController and the coordinator.
    final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            target?.userContentController(c, didReceive: m)
        }
    }

    static func wrap(_ fragment: String, fontSize: Double) -> String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>
        :root { color-scheme: light dark; }
        html { -webkit-text-size-adjust: none; }
        body { font-family: -apple-system, Georgia, serif; font-size: \(Int(fontSize))%; line-height: 1.6;
               margin: 0; padding: 18px 22px 120px; overflow-wrap: break-word; }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        a { color: #e8730c; }
        @media (prefers-color-scheme: dark) {
          body { background: #121212; color: #e2e2e2; }
          body * { color: inherit !important; background-color: transparent !important; }
        }
        </style></head><body>\(fragment)</body></html>
        """
    }

    static let script = """
    (function(){
      function frac(){var h=document.documentElement.scrollHeight-window.innerHeight;
        return h<=0?1:Math.min(1,Math.max(0,window.scrollY/h));}
      window.stacksReport=function(){window.webkit.messageHandlers.scroll.postMessage(frac());};
      var t=null;
      window.addEventListener('scroll',function(){ if(t)return;
        t=setTimeout(function(){t=null;stacksReport();},300);},{passive:true});
      document.addEventListener('click',function(e){
        var a=e.target.closest?e.target.closest('a'):null; if(!a)return;
        if(a.hasAttribute('kavita-page')){
          e.preventDefault(); e.stopPropagation();
          window.webkit.messageHandlers.link.postMessage({page:parseInt(a.getAttribute('kavita-page'),10),
            part:a.getAttribute('kavita-part')||''});
        }
      },true);
    })();
    """
}
