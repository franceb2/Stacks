import Foundation

// Runs the app's real importer on the made-up files and checks what comes out.
let dir = CommandLine.arguments[1]
var failures = 0

func check(_ ok: Bool, _ message: String) {
    print(ok ? "  ok   \(message)" : "  FAIL \(message)")
    if !ok { failures += 1 }
}

func run(_ file: String) -> ExtractedOrder? {
    print("\n== \(file)")
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(file)"))
        let doc = try ReadingOrderImporter.parse(data: data, filename: file)
        print("  title: \(doc.title ?? "-"), rows: \(doc.rows.count)")
        let x = OrderExtractor.extract(doc)
        for s in x.sections { print("  section \(s.id) \"\(s.name)\" \(s.count)\(s.mostlyRepeats ? " (repeats)" : "")") }
        for c in x.colors { print("  color \(c.id) \(c.name) \(c.count)\(c.isGray ? " gray" : "")") }
        for c in x.candidates {
            print("  [\(c.section)] \(c.color ?? "none")\t\(c.series) | \(c.number ?? "-") | y\(c.year.map(String.init) ?? "-") v\(c.volume.map(String.init) ?? "-")\(c.titleOnly ? " (title only)" : "") :: \(c.label)")
        }
        return x
    } catch {
        print("  error: \(error.localizedDescription)")
        failures += 1
        return nil
    }
}

func kept(_ x: ExtractedOrder, library: Set<String> = []) -> [ReadingOrder.Entry] {
    ReadingOrderBuilder.entries(x, colors: ReadingOrderBuilder.defaultColors(x),
                                sections: ReadingOrderBuilder.defaultSections(x), libraryKeys: library, hostName: "Hero")
}

if let x = run("hero.html") {
    let e = kept(x)
    let labels = e.map { "\($0.series)#\($0.number ?? "-")" }
    print("  kept: \(labels)")
    check(labels.first == "Hero#001", "starts with Hero #001")
    check(labels.contains("Hero/Bat#-"), "one-shot kept with clean name")
    check(!labels.contains { $0.hasPrefix("Curse of the Hero") }, "gray issues left out")
    check(labels.contains("Villain#3"), "range 2-4 expanded")
    check(labels.contains("Hero#4"), "two issues in one cell")
    check(labels.contains("Sidekick & Friends#2"), "en dash range")
    check(x.sections.first { $0.name == "RELEASE ORDER" }?.mostlyRepeats == true, "release order starts off")
    check(e.count == 11, "11 entries kept (got \(e.count))")
}

if let x = run("order.xlsx") {
    let e = kept(x)
    let labels = e.map { "\($0.series)#\($0.number ?? "-")" }
    print("  kept: \(labels)")
    check(labels.prefix(4) == ["Daredevil#1", "Daredevil#2", "Daredevil#3", "Daredevil#4"], "header columns used")
    check(e.first?.year == 1964, "year column used")
    check(labels.contains("Spider-Man#5"), "red row kept")
    check(!labels.contains("What If#7"), "gray row left out")
    check(e.contains { $0.series == "Daredevil" && $0.volume == 2 }, "Vol. 2 read from title")
    check(x.sections.count == 2, "each sheet is a part")
}

if let x = run("order.docx") {
    let e = kept(x)
    let labels = e.map { "\($0.series)#\($0.number ?? "-")" }
    print("  kept: \(labels)")
    check(labels.first == "Batman#1" && e.first?.year == 2016, "numbered list item with year")
    check(labels.contains("Batman Annual#2"), "red text kept")
    check(labels.contains("Detective Comics#1003"), "list with & and commas")
    check(labels.contains("Nightwing#5"), "table cell")
    check(!labels.contains("Robin#9"), "gray cell left out")
}

if let x = run("order.csv") {
    let labels = kept(x).map { "\($0.series)#\($0.number ?? "-")" }
    print("  kept: \(labels)")
    check(labels == ["Saga#1", "Saga#2", "Saga#3", "Paper Girls#1"], "csv columns")
}

if let x = run("order.txt") {
    let e = kept(x, library: [TitleKey.make("Invincible: Battle Beast")])
    let labels = e.map { "\($0.series)#\($0.number ?? "-")" }
    print("  kept: \(labels)")
    check(labels == ["Invincible#1", "Invincible#2", "Invincible#3", "Invincible#4", "Tech Jacket#1",
                     "Invincible: Battle Beast#-", "Invincible#5", "Invincible#6"], "text lines and headings")
}

// Links become download links.
let links = [
    ("https://docs.google.com/document/d/abc_123-X/edit?usp=sharing", "https://docs.google.com/document/d/abc_123-X/export?format=html"),
    ("docs.google.com/spreadsheets/d/SHEET/edit#gid=0", "https://docs.google.com/spreadsheets/d/SHEET/export?format=xlsx"),
    ("https://drive.google.com/file/d/FILE/view?usp=drive_link", "https://drive.google.com/uc?export=download&id=FILE"),
    ("https://drive.google.com/open?id=FILE2", "https://drive.google.com/uc?export=download&id=FILE2"),
]
print("\n== links")
for (input, expected) in links {
    check(ReadingOrderImporter.downloadURL(for: input)?.absoluteString == expected, input)
}
check(ImportColor.normalize("rgb(204, 0, 0)") == "#cc0000", "rgb() colors")
check(ImportColor.isGray("#666666") && !ImportColor.isGray("#000000") && !ImportColor.isGray("#cc0000"), "gray detection")

print(failures == 0 ? "\nAll importer checks passed" : "\n\(failures) importer checks failed")
exit(failures == 0 ? 0 : 1)
