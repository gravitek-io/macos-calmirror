#!/bin/bash
# generate-icon.sh — Render Resources/AppIcon.svg into Resources/AppIcon.icns
#
# The .icns is committed so that installers and CI do not need an SVG
# renderer; run this script after editing the SVG and commit the result.
#
# Rendering uses rsvg-convert (brew install librsvg) when available and falls
# back to the system QuickLook renderer (qlmanage) otherwise. The iconset is
# assembled with the standard macOS sizes and packed with iconutil.
#
# Usage:
#   ./scripts/generate-icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SVG="${PROJECT_DIR}/Resources/AppIcon.svg"
ICNS="${PROJECT_DIR}/Resources/AppIcon.icns"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="${WORK}/AppIcon.iconset"
MASTER="${WORK}/master.png"
mkdir -p "$ICONSET"

# ---------------------------------------------------------------------------
# Render the 1024x1024 master image
# ---------------------------------------------------------------------------
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1024 -h 1024 "$SVG" -o "$MASTER"
else
    echo "rsvg-convert not found, falling back to qlmanage"
    qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
    mv "${WORK}/$(basename "$SVG").png" "$MASTER"
fi

# ---------------------------------------------------------------------------
# Build the iconset (1x and 2x variants of every size macOS expects)
# ---------------------------------------------------------------------------
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "==> Wrote ${ICNS}"
