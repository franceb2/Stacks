import SwiftUI
import WebKit

/// Kavita-style book reader. Kavita splits a book into sections; each is shown either as pages you
/// turn (tap the sides or swipe) or as one long scroll. Kavita tracks the section; the exact spot
/// inside it is remembered on the phone.
struct EPUBReaderView: View {
    let context: ReaderContext
    let client: KavitaClient
    let actions: ReaderActions

    @EnvironmentObject private var downloads: Downloads
    @State private var prefs = ReaderPrefsStore.book
    @State private var section: Int
    @State private var content: SectionContent?
    @State private var start: BookStart
    @State private var toc: [BookTOCItem] = []
    @State private var error: String?
    @State private var showChrome = false
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var showEnd = false
    @State private var pageInSection = 0
    @State private var pagesInSection = 1
    @State private var command: BookCommand?

    init(context: ReaderContext, client: KavitaClient, actions: ReaderActions) {
        self.context = context
        self.client = client
        self.actions = actions
        _section = State(initialValue: context.startPage)
        if let saved = LocalBookPosition.load(chapterId: context.chapterId), saved.section == context.startPage {
            _start = State(initialValue: .fraction(saved.fraction))
        } else {
            _start = State(initialValue: .top)
        }
    }

    private var sectionCount: Int { max(context.info.pages, 1) }

    var body: some View {
        ZStack {
            Color(cssHex: prefs.theme.background).ignoresSafeArea()

            if showEnd {
                EndOfChapterView(actions: actions)
            } else if let content {
                BookWebView(content: content, baseURL: client.baseURL, folder: downloads.folder(context.chapterId),
                            prefs: prefs, start: start, command: command, onEvent: handle)
                    .ignoresSafeArea()
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).multilineTextAlignment(.center)
                    Button("Try again") { Task { await loadSection() } }.buttonStyle(SecondaryButtonStyle())
                    Button("Close") { actions.close() }.buttonStyle(SecondaryButtonStyle())
                }
                .foregroundStyle(Color(cssHex: prefs.theme.text))
                .padding()
            } else {
                ProgressView()
            }

            if showChrome { chrome.transition(.opacity) }
        }
        .statusBarHidden(!showChrome)
        .preferredColorScheme(prefs.theme.isDark ? .dark : .light)
        .task { toc = (try? await client.bookTOC(chapterId: context.chapterId)) ?? [] }
        .task(id: section) { await loadSection() }
        .onChange(of: prefs) { _, value in ReaderPrefsStore.book = value }
        .sheet(isPresented: $showSettings) {
            BookSettingsSheet(prefs: $prefs).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTOC) { tocSheet }
        .onReceive(NotificationCenter.default.publisher(for: .tourShowMenu)) { _ in showChrome = true }
        .onReceive(NotificationCenter.default.publisher(for: .tourCloseReader)) { _ in
            showSettings = false
            showTOC = false
        }
    }

    // MARK: Menu

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { actions.close() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
                }
                Text(context.seriesName).font(.headline).lineLimit(1)
                Spacer()
                if context.offline { Image(systemName: "wifi.slash").foregroundStyle(Theme.muted) }
                if !toc.isEmpty {
                    Button { showTOC = true } label: {
                        Image(systemName: "list.bullet").font(.headline).frame(width: 36, height: 36)
                    }
                }
                Button { showSettings = true } label: {
                    Image(systemName: "textformat.size").font(.headline).frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.black.opacity(0.88))

            Spacer()

            HStack(spacing: 18) {
                Button { go(to: section - 1, start: .top) } label: { Image(systemName: "backward.end.fill") }
                    .disabled(section == 0)
                Button { command = BookCommand(js: "stacksPrev()") } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 2) {
                    Text("Section \(section + 1) of \(sectionCount)").font(.footnote.monospacedDigit())
                    if prefs.paged && pagesInSection > 1 {
                        Text("Page \(pageInSection + 1) of \(pagesInSection)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Button { command = BookCommand(js: "stacksNext()") } label: { Image(systemName: "chevron.right") }
                Button {
                    if section < sectionCount - 1 { go(to: section + 1, start: .top) } else { showEnd = true }
                } label: { Image(systemName: "forward.end.fill") }
            }
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Color.black.opacity(0.88))
        }
        .foregroundStyle(.white)
        .tint(Theme.primary)
    }

    private var tocSheet: some View {
        NavigationStack {
            List(flatten(toc)) { entry in
                Button {
                    showTOC = false
                    go(to: entry.item.page, start: .top)
                } label: {
                    HStack {
                        Text(entry.item.title ?? "Section \(entry.item.page + 1)")
                            .padding(.leading, CGFloat(entry.depth) * 16)
                            .foregroundStyle(entry.item.page == section ? Theme.primary : Theme.text)
                        Spacer()
                        if downloads.sectionURL(chapterId: context.chapterId, section: entry.item.page) != nil {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.primary).font(.caption)
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .kavitaBackground()
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTOC = false } } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Navigation

    private func go(to newSection: Int, start newStart: BookStart) {
        guard newSection >= 0, newSection < sectionCount else { return }
        showEnd = false
        start = newStart
        if newSection == section {
            if case .part(let id) = newStart { command = BookCommand(js: "stacksStart('part', \(id.jsQuoted))") }
            return
        }
        section = newSection
    }

    private func handle(_ event: BookEvent) {
        switch event {
        case .position(let fraction, let page, let pages):
            pageInSection = page
            pagesInSection = pages
            LocalBookPosition.save(chapterId: context.chapterId, section: section, fraction: fraction)
            if section >= sectionCount - 1 && fraction >= 0.98 { actions.finished() }
        case .edgeNext:
            if section < sectionCount - 1 { go(to: section + 1, start: .top) } else { showEnd = true }
        case .edgePrevious:
            if section > 0 { go(to: section - 1, start: .end) }
        case .toggleMenu:
            withAnimation(.easeOut(duration: 0.15)) { showChrome.toggle() }
        case .link(let page, let part):
            go(to: page, start: part.map { BookStart.part($0) } ?? BookStart.top)
        }
    }

    private func loadSection() async {
        content = nil
        error = nil
        if let local = downloads.sectionURL(chapterId: context.chapterId, section: section) {
            content = .file(local, section)
            actions.pageChanged(section)
            return
        }
        if context.offline {
            error = "Section \(section + 1) isn't downloaded."
            return
        }
        do {
            let html = try await client.bookPageHTML(chapterId: context.chapterId, page: section)
            content = .html(html, section)
            actions.pageChanged(section)
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server." : error.localizedDescription
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

// MARK: - Settings

struct BookSettingsSheet: View {
    @Binding var prefs: BookPrefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Layout", selection: $prefs.paged) {
                        Text("Pages").tag(true)
                        Text("Scroll").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Tap sides to turn pages", isOn: $prefs.tapToTurn)
                        .disabled(!prefs.paged)
                }
                .listRowBackground(Theme.card)

                Section("Theme") {
                    HStack(spacing: 14) {
                        ForEach(BookTheme.allCases) { theme in
                            Button {
                                prefs.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    Text("Aa")
                                        .font(.headline)
                                        .foregroundStyle(Color(cssHex: theme.text))
                                        .frame(width: 52, height: 40)
                                        .background(Color(cssHex: theme.background), in: RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(prefs.theme == theme ? Theme.primary : Color.white.opacity(0.2),
                                                    lineWidth: prefs.theme == theme ? 2 : 1))
                                    Text(theme.label).font(.caption2).foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.card)

                Section("Text") {
                    Picker("Font", selection: $prefs.font) {
                        ForEach(BookFont.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Size \(prefs.fontSize)%", value: $prefs.fontSize, in: 60...250, step: 10)
                    Stepper(String(format: "Line spacing %.1f", prefs.lineHeight), value: $prefs.lineHeight,
                            in: 1.0...2.4, step: 0.1)
                    Stepper("Margins \(prefs.margin)", value: $prefs.margin, in: 8...60, step: 4)
                }
                .listRowBackground(Theme.card)
            }
            .kavitaBackground()
            .navigationTitle("Reading settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
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

enum SectionContent: Equatable {
    case html(String, Int)
    case file(URL, Int)

    var key: String {
        switch self {
        case .html(let s, let n): return "h\(n)-\(s.count)"
        case .file(let u, let n): return "f\(n)-\(u.path)"
        }
    }
}

enum BookStart: Equatable {
    case top, end
    case fraction(Double)
    case part(String)
}

struct BookCommand: Equatable {
    let id = UUID()
    let js: String
}

enum BookEvent {
    case position(fraction: Double, page: Int, pages: Int)
    case edgeNext, edgePrevious, toggleMenu
    case link(page: Int, part: String?)
}

struct BookWebView: UIViewRepresentable {
    let content: SectionContent
    let baseURL: URL
    let folder: URL
    let prefs: BookPrefs
    let start: BookStart
    let command: BookCommand?
    let onEvent: (BookEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(WeakMessageHandler(context.coordinator), name: "book")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        context.coordinator.webView = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.onEvent = onEvent
        web.scrollView.isScrollEnabled = !prefs.paged
        web.scrollView.showsVerticalScrollIndicator = !prefs.paged

        let key = content.key
        if c.loadedKey != key || c.loadedPrefs != prefs {
            let samePage = c.loadedKey == key
            c.loadedKey = key
            c.loadedPrefs = prefs
            // When only the settings changed, come back to the same spot.
            c.pendingStart = samePage ? .fraction(c.lastFraction) : start
            load(web)
        }
        if let command, command != c.lastCommand {
            c.lastCommand = command
            web.evaluateJavaScript(command.js)
        }
    }

    private func load(_ web: WKWebView) {
        switch content {
        case .html(let html, _):
            web.loadHTMLString(Self.wrap(html, prefs: prefs), baseURL: baseURL)
        case .file(let url, _):
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let view = folder.appendingPathComponent("view.html")
            try? Self.wrap(raw, prefs: prefs).write(to: view, atomically: true, encoding: .utf8)
            web.loadFileURL(view, allowingReadAccessTo: folder)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onEvent: (BookEvent) -> Void
        weak var webView: WKWebView?
        var loadedKey: String?
        var loadedPrefs: BookPrefs?
        var pendingStart: BookStart = .top
        var lastCommand: BookCommand?
        var lastFraction: Double = 0

        init(onEvent: @escaping (BookEvent) -> Void) { self.onEvent = onEvent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js: String
            switch pendingStart {
            case .top: js = "stacksStart('fraction', 0)"
            case .end: js = "stacksStart('end', 0)"
            case .fraction(let f): js = "stacksStart('fraction', \(f))"
            case .part(let id): js = "stacksStart('part', \(id.jsQuoted))"
            }
            // Give the column layout a moment to settle before positioning.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { webView.evaluateJavaScript(js) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Links to the outside web open in Safari instead of replacing the book.
            if action.navigationType == .linkActivated, let url = action.request.url,
               let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "pos":
                let fraction = (body["fraction"] as? Double) ?? Double(body["fraction"] as? Int ?? 0)
                lastFraction = fraction
                onEvent(.position(fraction: fraction, page: body["page"] as? Int ?? 0,
                                  pages: body["pages"] as? Int ?? 1))
            case "edge":
                onEvent((body["dir"] as? String) == "prev" ? .edgePrevious : .edgeNext)
            case "menu":
                onEvent(.toggleMenu)
            case "link":
                guard let page = body["page"] as? Int else { return }
                let part = (body["part"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                onEvent(.link(page: page, part: part))
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

    static func wrap(_ fragment: String, prefs: BookPrefs) -> String {
        let m = prefs.margin
        let font = prefs.font.css.map { "body, body * { font-family: \($0) !important; }" } ?? ""
        let layout = prefs.paged
            ? """
              html { height: 100%; overflow: hidden; }
              body { height: 100vh; box-sizing: border-box; margin: 0;
                     padding: max(44px, env(safe-area-inset-top)) \(m)px max(36px, env(safe-area-inset-bottom)) \(m)px;
                     column-width: calc(100vw - \(m * 2)px); column-gap: \(m * 2)px; column-fill: auto; }
              img, svg, video, table { max-height: calc(100vh - 110px) !important; break-inside: avoid; }
              """
            : """
              body { margin: 0; padding: max(56px, env(safe-area-inset-top)) \(m)px 140px \(m)px; }
              """
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html { -webkit-text-size-adjust: none; background: \(prefs.theme.background); }
        body { background: \(prefs.theme.background); color: \(prefs.theme.text);
               font-size: \(prefs.fontSize)%; line-height: \(prefs.lineHeight); overflow-wrap: break-word;
               -webkit-user-select: none; }
        body * { color: inherit !important; background-color: transparent !important; }
        p, div, li, span { line-height: \(prefs.lineHeight) !important; }
        img, svg, video { max-width: 100% !important; height: auto !important; object-fit: contain; }
        a, a * { color: \(AppTheme.current.accentCSS) !important; }
        \(font)
        \(layout)
        </style></head><body>\(fragment)
        <script>\(script(paged: prefs.paged, tapToTurn: prefs.tapToTurn))</script>
        </body></html>
        """
    }

    private static func script(paged: Bool, tapToTurn: Bool) -> String {
        """
        (function(){
          var paged = \(paged ? "true" : "false");
          var tapToTurn = \(tapToTurn ? "true" : "false");
          function post(m){ window.webkit.messageHandlers.book.postMessage(m); }
          function W(){ return window.innerWidth; }
          function docH(){ return document.documentElement.scrollHeight; }
          function count(){ return paged ? Math.max(1, Math.round(document.body.scrollWidth / W())) : 1; }
          function cur(){ return paged ? Math.round(window.scrollX / W()) : 0; }
          function frac(){
            if (paged) { var c = count(); return c <= 1 ? 1 : cur() / (c - 1); }
            var h = docH() - window.innerHeight; return h <= 0 ? 1 : Math.min(1, Math.max(0, window.scrollY / h));
          }
          function report(){ post({type:'pos', fraction: frac(), page: cur(), pages: count()}); }
          window.stacksGoPage = function(n){
            n = Math.max(0, Math.min(count() - 1, n)); window.scrollTo(n * W(), 0); report();
          };
          window.stacksNext = function(){
            if (!paged) {
              if (window.scrollY >= docH() - window.innerHeight - 2) { post({type:'edge', dir:'next'}); return; }
              window.scrollBy({top: window.innerHeight * 0.9, behavior: 'smooth'}); return;
            }
            if (cur() < count() - 1) stacksGoPage(cur() + 1); else post({type:'edge', dir:'next'});
          };
          window.stacksPrev = function(){
            if (!paged) {
              if (window.scrollY <= 2) { post({type:'edge', dir:'prev'}); return; }
              window.scrollBy({top: -window.innerHeight * 0.9, behavior: 'smooth'}); return;
            }
            if (cur() > 0) stacksGoPage(cur() - 1); else post({type:'edge', dir:'prev'});
          };
          window.stacksStart = function(kind, val){
            if (kind === 'end') {
              if (paged) stacksGoPage(count() - 1); else window.scrollTo(0, docH());
            } else if (kind === 'part') {
              var el = document.getElementById(val) || document.getElementsByName(val)[0];
              if (el) {
                if (paged) stacksGoPage(Math.floor((el.getBoundingClientRect().left + window.scrollX) / W()));
                else el.scrollIntoView();
              }
            } else {
              if (paged) stacksGoPage(Math.round(val * (count() - 1)));
              else window.scrollTo(0, val * (docH() - window.innerHeight));
            }
            report();
          };
          var t = null;
          window.addEventListener('scroll', function(){
            if (t) return; t = setTimeout(function(){ t = null; report(); }, 250);
          }, {passive: true});
          var lastFrac = 0;
          window.addEventListener('resize', function(){ if (paged) stacksGoPage(Math.round(lastFrac * (count() - 1))); });
          var sx = 0, sy = 0, swiped = false;
          document.addEventListener('touchstart', function(e){
            sx = e.touches[0].clientX; sy = e.touches[0].clientY; swiped = false; lastFrac = frac();
          }, {passive: true});
          document.addEventListener('touchend', function(e){
            if (!paged) return;
            var dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy;
            if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { swiped = true; if (dx < 0) stacksNext(); else stacksPrev(); }
          }, {passive: true});
          document.addEventListener('click', function(e){
            if (swiped) { swiped = false; return; }
            var a = e.target.closest ? e.target.closest('a') : null;
            if (a && a.hasAttribute('kavita-page')) {
              e.preventDefault(); e.stopPropagation();
              post({type:'link', page: parseInt(a.getAttribute('kavita-page'), 10), part: a.getAttribute('kavita-part') || ''});
              return;
            }
            if (a && a.getAttribute('href') && a.getAttribute('href').indexOf('javascript') !== 0) return;
            var x = e.clientX / W();
            if (paged && tapToTurn && x < 0.3) stacksPrev();
            else if (paged && tapToTurn && x > 0.7) stacksNext();
            else post({type:'menu'});
          }, true);
        })();
        """
    }
}

extension String {
    /// A JavaScript string literal for this text.
    var jsQuoted: String {
        let data = try? JSONEncoder().encode(self)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "''"
    }
}

extension Color {
    /// "#rrggbb"
    init(cssHex: String) {
        let hex = UInt32(cssHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(hex: hex)
    }
}
