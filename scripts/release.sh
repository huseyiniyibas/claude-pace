#!/bin/bash
# Builds a universal ClaudePace.app and packs it for a GitHub release, in dist/release/:
#   ClaudePace-<version>.zip
#   ClaudePace-<version>.zip.sha256
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
#
# It builds in dist/release rather than dist, so an app you are running from dist/ is
# not replaced underneath you. Before packing it checks that the app does not carry
# anything from this machine: the build must not embed your home folder or user name,
# since the zip is public.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>, for example 0.1.0}"
OUT_DIR="dist/release"
VERSION="$VERSION" OUT_DIR="$OUT_DIR" ./scripts/make-app.sh --universal

BIN="$OUT_DIR/ClaudePace.app/Contents/MacOS/ClaudePace"
if strings -a "$BIN" | grep -F -q -e "$HOME" -e "/Users/$USER"; then
    echo "Refusing to package: the binary contains this machine's home path or user name:" >&2
    strings -a "$BIN" | grep -F -e "$HOME" -e "/Users/$USER" | sort -u | head -5 >&2
    exit 1
fi

lipo -archs "$BIN" | grep -q arm64  || { echo "Missing arm64 slice" >&2; exit 1; }
lipo -archs "$BIN" | grep -q x86_64 || { echo "Missing x86_64 slice" >&2; exit 1; }

ZIP="$OUT_DIR/ClaudePace-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$OUT_DIR/ClaudePace.app" "$ZIP"
(cd "$OUT_DIR" && shasum -a 256 "ClaudePace-$VERSION.zip" > "ClaudePace-$VERSION.zip.sha256")

echo "Built $ZIP"
cat "$ZIP.sha256"
