#!/bin/bash
# Builds dist/ClaudePace.app: a menu bar app (no Dock icon) you can drag to Applications.
#
#   ./scripts/make-app.sh               build for this Mac
#   ./scripts/make-app.sh --universal   build for Apple Silicon and Intel
#
# VERSION=1.2.3 sets the version shown in the app's Info.plist (default 0.1.0).
# OUT_DIR=somewhere puts the app there instead of in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-dist}"
ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

# The ${array[@]+...} form keeps an empty array from failing under `set -u` in the
# older bash that ships with macOS.
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/ClaudePace"

APP="$OUT_DIR/ClaudePace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudePace"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ClaudePace</string>
    <key>CFBundleIdentifier</key><string>com.claudepace.app</string>
    <key>CFBundleName</key><string>Claude Pace</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on the Mac that built it. A download from the
# internet is quarantined and needs the "Open Anyway" step described in the README,
# because there is no Developer ID signature or notarization.
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
