#!/bin/zsh
# Regenerate docs/screenshots/*.png from ReadmeScreenshotTests.
#
# Run from the repo root:
#     ./scripts/capture_readme_screenshots.sh [simulator-name]
#
# Produces media.png, assistant.png and settings.png. The Camera screen is not
# captured: under `-ui-testing` the app disables camera hardware and labels the screen
# as such, so a simulator shot would show the test harness rather than the product.

set -eu

SIM_NAME="${1:-iPhone 17e}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$(mktemp -d)"
OUT="$ROOT/docs/screenshots"

cd "$ROOT"

echo "→ running ReadmeScreenshotTests on $SIM_NAME"
xcodebuild test \
  -project CameraHuman.xcodeproj \
  -scheme CameraHuman \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" \
  -only-testing:CameraHumanUITests/ReadmeScreenshotTests \
  >/dev/null

RESULT="$(ls -td "$DD"/Logs/Test/*.xcresult | head -1)"
ATTACH="$(mktemp -d)"

echo "→ exporting attachments"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$ATTACH" >/dev/null

mkdir -p "$OUT"
python3 - "$ATTACH" "$OUT" <<'PY'
import json, shutil, sys, os
attach, out = sys.argv[1], sys.argv[2]
wanted = {"media", "assistant", "settings"}
found = 0
for group in json.load(open(os.path.join(attach, "manifest.json"))):
    for a in group.get("attachments", []):
        # XCTAttachment names come back as "<name>_<index>_<uuid>.png"
        base = a.get("suggestedHumanReadableName", "").split("_")[0]
        if base in wanted:
            shutil.copy(os.path.join(attach, a["exportedFileName"]),
                        os.path.join(out, base + ".png"))
            print(f"  {base}.png")
            found += 1
if found != len(wanted):
    raise SystemExit(f"expected {len(wanted)} screenshots, got {found}")
PY

rm -rf "$DD" "$ATTACH"
echo "→ written to docs/screenshots/"
