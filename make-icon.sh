#!/bin/bash
# Turn the approved artwork into all standard Mac icon representations.
set -euo pipefail
cd "$(dirname "$0")"
ICONSET=.build/RoseFinance.iconset
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Assets/Rose.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    RETINA=$((SIZE * 2))
    sips -z "$RETINA" "$RETINA" Assets/Rose.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output .build/RoseFinance.icns
