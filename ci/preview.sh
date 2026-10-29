#!/bin/bash
# Builds Stacks for the iPhone simulator, runs it against a real Kavita filled with sample books,
# records a video of the automatic tour, saves screenshots, and writes the preview page into ./site
set -euo pipefail

ROOT="$PWD"
WORK="${RUNNER_TEMP:-/tmp}/preview"
OUT="$ROOT/site"
PORT=5055 # macOS keeps 5000 for AirPlay
BUNDLE=io.github.stacksreader.Stacks
mkdir -p "$WORK" "$OUT"

echo "::group::Sample library"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet pillow
"$WORK/venv/bin/python" ci/make_samples.py "$WORK/library"
echo "::endgroup::"

echo "::group::Start Kavita"
if [ "$(uname -m)" = "arm64" ]; then KARCH=arm64; else KARCH=x64; fi
curl -fsSL -o "$WORK/kavita.tgz" "https://github.com/Kareadita/Kavita/releases/latest/download/kavita-osx-$KARCH.tar.gz"
tar -xzf "$WORK/kavita.tgz" -C "$WORK"
chmod +x "$WORK/Kavita/Kavita"
codesign --force -s - "$WORK/Kavita/Kavita" 2>/dev/null || true
mkdir -p "$WORK/Kavita/config"
python3 - "$WORK/Kavita/config/appsettings.json" "$PORT" <<'EOF'
import base64, json, secrets, sys
json.dump({"TokenKey": base64.b64encode(secrets.token_bytes(128)).decode(), "Port": int(sys.argv[2]),
           "IpAddresses": "", "BaseUrl": "/", "Cache": 75, "AllowIFraming": False}, open(sys.argv[1], "w"), indent=2)
EOF
(cd "$WORK/Kavita" && nohup ./Kavita > "$WORK/kavita.log" 2>&1 &)
for _ in $(seq 1 90); do
  curl -fs -o /dev/null "http://localhost:$PORT/api/health" && break
  sleep 2
done
curl -fs -o /dev/null "http://localhost:$PORT/api/health" || { echo "::error::Kavita did not start"; tail -60 "$WORK/kavita.log"; exit 1; }
KEY=$(python3 ci/seed_kavita.py "http://localhost:$PORT" "$WORK/library" | tail -1)
echo "::endgroup::"

echo "::group::Build for simulator"
xcodegen generate
xcodebuild -project Stacks.xcodeproj -target Stacks -configuration Release \
  -sdk iphonesimulator ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO SYMROOT="$WORK/build" \
  CODE_SIGNING_ALLOWED=NO build -quiet
APP="$WORK/build/Release-iphonesimulator/Stacks.app"
test -d "$APP"
echo "::endgroup::"

echo "::group::Boot simulator"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.split("iOS")[-1])]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    for d in items:
        name = d["name"]
        plain = not re.search(r"Max|Plus|SE|mini|Air|\d+e\b", name)
        if name.startswith("iPhone") and plain:
            key = (version(runtime), name)
            if best is None or key > best[0]:
                best = (key, d["udid"], runtime, name)
if best is None:
    for runtime, items in devices.items():
        for d in items:
            if "iOS" in runtime and d["name"].startswith("iPhone"):
                best = (None, d["udid"], runtime, d["name"])
print(best[1])
print(best[3], "on", best[2], file=sys.stderr)
')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
echo "::endgroup::"

run_tour() { # $1 = light|dark, $2 = record video (yes/no)
  xcrun simctl ui "$UDID" appearance "$1"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  local data
  xcrun simctl launch "$UDID" "$BUNDLE" -demoServer "http://localhost:$PORT" -demoApiKey "$KEY" -demoTour NO >/dev/null
  sleep 2
  data=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  rm -rf "$data/Documents/tour"
  xcrun simctl terminate "$UDID" "$BUNDLE" || true
  sleep 1

  local rec=""
  if [ "$2" = "yes" ]; then
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/tour.mp4" &
    rec=$!
    sleep 2
  fi
  xcrun simctl launch "$UDID" "$BUNDLE" -demoServer "http://localhost:$PORT" -demoApiKey "$KEY" -demoTour YES >/dev/null
  for _ in $(seq 1 150); do
    [ -f "$data/Documents/tour/done.txt" ] && break
    sleep 1
  done
  if [ -n "$rec" ]; then
    kill -INT "$rec" || true
    wait "$rec" || true
  fi
  [ -f "$data/Documents/tour/done.txt" ] || echo "::warning::Tour ($1) did not finish; page may be missing screenshots"
  for f in "$data"/Documents/tour/*.png; do
    [ -e "$f" ] || continue
    cp "$f" "$OUT/$(basename "$f" .png)-$1.png"
  done
}

echo "::group::Tour (light)"
run_tour light yes
echo "::endgroup::"
echo "::group::Tour (dark)"
run_tour dark no
echo "::endgroup::"

python3 ci/make_page.py "$OUT"
ls -la "$OUT"
