"""Sets up a fresh Kavita for preview screenshots: account, libraries, scan, and some reading progress.

Usage: python seed_kavita.py BASE_URL LIBRARY_DIR
Prints the Auth Key on the last line.
"""
import json
import sys
import time
import urllib.request

BASE, LIB = sys.argv[1].rstrip("/"), sys.argv[2].rstrip("/")
KEY = None


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Accept", "application/json")
    req.add_header("Content-Type", "application/json")
    if KEY:
        req.add_header("x-api-key", KEY)
    data = json.dumps(body).encode() if body is not None else (b"" if method == "POST" else None)
    with urllib.request.urlopen(req, data, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


user = call("POST", "/api/Account/register", {"username": "demo", "email": "", "password": "DemoPass123!"})
KEY = user["apiKey"]

# (name, library type, folder, file types, metadata provider Kavita accepts for that type)
libraries = [("Comics", 1, "comics", [1, 4], 2), ("Manga", 0, "manga", [1, 4], 3), ("Books", 2, "books", [2, 3], 2)]
for name, kind, folder, groups, provider in libraries:
    call("POST", "/api/Library/create", {
        "id": 0, "name": name, "type": kind, "folders": [f"{LIB}/{folder}"], "folderWatchMode": 0,
        "includeInDashboard": True, "includeInSearch": True, "manageCollections": True, "manageReadingLists": True,
        "allowScrobbling": False, "allowMetadataMatching": False, "enableMetadata": True,
        "removePrefixForSortName": False, "inheritWebLinksFromFirstChapter": False, "defaultLanguage": "",
        "metadataProvider": provider, "fileGroupTypes": groups, "excludePatterns": []})

libs = {l["name"]: l["id"] for l in call("GET", "/api/Library/libraries")}


def series_in(lib_id):
    return call("POST", "/api/Series/all-v2?PageNumber=1&PageSize=50", {
        "id": 0, "statements": [{"comparison": 0, "field": 19, "value": str(lib_id)}],
        "combination": 1, "sortOptions": {"sortField": 1, "isAscending": True}, "limitTo": 0})


expected = {"Comics": 4, "Manga": 1, "Books": 2}
# Kavita drops scan requests that arrive while another scan runs, so scan one library at a time
# and ask again if nothing shows up.
for name, lib_id in libs.items():
    deadline = time.time() + 180
    last_request = 0
    while len(series_in(lib_id)) < expected[name]:
        if time.time() > deadline:
            sys.exit(f"Scan of {name} did not finish")
        if time.time() - last_request > 20:
            call("POST", f"/api/Library/scan?libraryId={lib_id}&force=true")
            last_request = time.time()
        time.sleep(2)
time.sleep(5)  # let covers finish generating


def chapters(series_id):
    d = call("GET", f"/api/Series/series-detail?seriesId={series_id}")
    out = [c for v in sorted(d["volumes"], key=lambda v: v["minNumber"]) for c in v["chapters"]]
    seen = {c["id"] for c in out}
    out += [c for c in d["chapters"] + d["specials"] if c["id"] not in seen]
    return out


def set_page(chapter_id, page):
    info = call("GET", f"/api/Reader/chapter-info?chapterId={chapter_id}")
    call("POST", "/api/Reader/progress", {
        "volumeId": info["volumeId"], "chapterId": chapter_id, "pageNum": page, "seriesId": info["seriesId"],
        "libraryId": info["libraryId"], "bookScrollId": None})


def by_name(lib, name):
    return next(s for s in series_in(libs[lib]) if s["name"] == name)


# Comics: Atlas Rising issues 1-2 read, issue 3 half way; Starfall started.
atlas = chapters(by_name("Comics", "Atlas Rising")["id"])
set_page(atlas[0]["id"], atlas[0]["pages"])
set_page(atlas[1]["id"], atlas[1]["pages"])
set_page(atlas[2]["id"], 5)
starfall = chapters(by_name("Comics", "Starfall")["id"])
set_page(starfall[0]["id"], 3)

# Manga: volume 1 read, volume 2 started.
moon = chapters(by_name("Manga", "Moon Garden")["id"])
set_page(moon[0]["id"], moon[0]["pages"])
set_page(moon[1]["id"], 3)

# Book: on section 2.
river = chapters(by_name("Books", "The River Road")["id"])
set_page(river[0]["id"], 1)

print(KEY)
