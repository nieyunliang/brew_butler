#!/usr/bin/env bash
# Generates the macOS app icon PNGs from the SVG masters.
# Requires: rsvg-convert (brew install librsvg)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/design/app-icon"
OUT="$ROOT/Brewbutler/Assets.xcassets/AppIcon.appiconset"
MAIN="$SRC/Brewbutler-icon.svg"
SMALL="$SRC/Brewbutler-icon-16.svg"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. Install it with: brew install librsvg" >&2
  exit 1
fi

mkdir -p "$OUT"

render() {
  local svg="$1" px="$2" file="$3"
  rsvg-convert -w "$px" -h "$px" "$svg" -o "$OUT/$file"
  printf '  %-22s %4spx\n' "$file" "$px"
}

echo "Rendering Brewbutler app icon -> $OUT"
# 16pt uses the simplified mark: the bow tie is dropped so it stays legible.
render "$SMALL" 16 "icon_16x16.png"
render "$MAIN"  32 "icon_16x16@2x.png"
render "$MAIN"  32 "icon_32x32.png"
render "$MAIN"  64 "icon_32x32@2x.png"
render "$MAIN" 128 "icon_128x128.png"
render "$MAIN" 256 "icon_128x128@2x.png"
render "$MAIN" 256 "icon_256x256.png"
render "$MAIN" 512 "icon_256x256@2x.png"
render "$MAIN" 512 "icon_512x512.png"
render "$MAIN" 1024 "icon_512x512@2x.png"
echo "Done."
