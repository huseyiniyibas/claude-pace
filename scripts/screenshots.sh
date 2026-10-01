#!/bin/bash
# Regenerates the images in docs/images from the app's demo mode: fixed numbers, nothing
# read from your account, nothing stored.
#
#   bar-*.png      The bar text, drawn offscreen by the app itself. No windows open and
#                  no permissions are needed.
#   dropdown.png, show-in-bar.png
#                  Real captures of the app's own menu windows, and only those. They need
#                  Screen Recording permission for your terminal, and a menu opens on
#                  screen for a couple of seconds each time.
#
# Usage: scripts/screenshots.sh [--bars-only]
set -euo pipefail
cd "$(dirname "$0")/.."

BARS_ONLY=0
[[ "${1:-}" == "--bars-only" ]] && BARS_ONLY=1

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudePace"
OUT="docs/images"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Bar options as JSON: win <isShown> <showsLabel> <fields>, opts <session> <weekly>.
win() { echo "{\"isShown\":$1,\"showsLabel\":$2,\"fields\":$3}"; }
opts() { echo "{\"session\":$1,\"weekly\":$2}"; }
DEFAULT_FIELDS='["percent","timeLeft","keyword"]'

# bar <name> <options-json>: the bar in light and dark. Empty options mean the defaults.
bar() {
    local mode
    for mode in light dark; do
        local flags=()
        [[ "$mode" == "dark" ]] && flags=(--dark)
        CLAUDEPACE_OPTIONS="$2" "$BIN" --demo --render-bar "$OUT/$1-$mode.png" ${flags[@]+"${flags[@]}"}
    done
}

bar bar-default ""
bar bar-percentage "$(opts "$(win true true '["percent"]')" "$(win true true '["percent"]')")"
bar bar-keyword "$(opts "$(win true true '["keyword"]')" "$(win true true '["keyword"]')")"
bar bar-no-names "$(opts "$(win true false "$DEFAULT_FIELDS")" "$(win true false "$DEFAULT_FIELDS")")"
bar bar-time-to-limit "$(opts "$(win true true '["percent","timeLeft","limitIn","keyword"]')" "$(win true true "$DEFAULT_FIELDS")")"
bar bar-mixed "$(opts "$(win true false '["keyword"]')" "$(win true true '["percent","timeLeft"]')")"
bar bar-session-only "$(opts "$(win true true "$DEFAULT_FIELDS")" "$(win false true "$DEFAULT_FIELDS")")"
bar bar-keywords-only "$(opts "$(win true false '["keyword"]')" "$(win true false '["keyword"]')")"

swiftc -O scripts/strip-metadata.swift -o "$TMP/strip-metadata"

if [[ "$BARS_ONLY" == "1" ]]; then
    "$TMP/strip-metadata" "$OUT"/bar-*.png
    echo "Bar images written to $OUT"
    exit 0
fi

swiftc -O scripts/window-bounds.swift -o "$TMP/window-bounds"

# menu <name> <flag> <options-json>: opens one menu of the demo app and captures only
# that menu's window, always in the dark look. A menu is translucent, so how it looks
# depends on what is behind it; the dark look comes out opaque and true to the real
# thing, while the light one does not, which is why there is no light version.
# The bar is kept short so the menu bar item is not hidden by the notch, because a
# hidden item cannot open its menu.
menu() {
    local attempt pid id wait_seconds
    # A menu can fail to open if another menu is open at that moment, so wait for
    # the window to appear and try again from a fresh launch if it does not.
    for attempt in 1 2 3; do
        CLAUDEPACE_OPTIONS="$3" "$BIN" --demo --screenshot "$2" --dark >/dev/null &
        pid=$!
        id=""
        for wait_seconds in 1 2 3 4 5 6 7 8; do
            sleep 1
            id="$("$TMP/window-bounds" "$pid" | awk '$2 >= 101 { print $1; exit }')"
            [[ -n "$id" ]] && break
        done
        if [[ -n "$id" ]]; then
            sleep 0.5 # let the menu finish drawing
            screencapture -x -o -l"$id" "$OUT/$1.png"
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 0
        fi
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    echo "No menu window found for $1 after 3 tries. Is Screen Recording allowed for this terminal?" >&2
    exit 1
}

SHORT_BAR="$(opts "$(win true false '["keyword"]')" "$(win false false '["keyword"]')")"
menu dropdown --open-menu "$SHORT_BAR"

# The Show in Bar menu, set up so the two windows visibly differ.
DIFFERENT="$(opts "$(win true true '["percent","timeLeft","limitIn","keyword"]')" "$(win true false '["percent","keyword"]')")"
menu show-in-bar --open-options "$DIFFERENT"

# Strip EXIF, XMP and comments from everything that is going to be published.
"$TMP/strip-metadata" "$OUT"/*.png
echo "Images written to $OUT"
