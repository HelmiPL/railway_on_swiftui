#!/bin/sh
# Packages Railway.app into a drag-to-install disk image with a custom background.
# Usage: Scripts/make-dmg.sh [path/to/Railway.app] [output.dmg]
# Uses dmgbuild (https://github.com/dmgbuild/dmgbuild), installed on first run into a cached virtualenv.
set -eu

SRCROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$SRCROOT/build/Railway.app}"
OUT="${2:-$SRCROOT/build/Railway.dmg}"

VENV="$HOME/Library/Caches/RailwayDMG/venv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet dmgbuild
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Window background, with a @2x representation for Retina displays
swift "$SRCROOT/Scripts/make-dmg-background.swift" "$WORK/background.png" 1
swift "$SRCROOT/Scripts/make-dmg-background.swift" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" 2>/dev/null

rm -f "$OUT"
"$VENV/bin/dmgbuild" -s "$SRCROOT/Scripts/dmg-settings.py" -D app="$APP" -D background="$WORK/background.tiff" "Railway" "$OUT"
echo "Created $OUT"
