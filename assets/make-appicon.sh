#!/bin/bash
# Regenerate the macOS app icon (assets/AppIcon.icns + iconset) from logo.png.
# Design: orange flame on a dark charcoal squircle (macOS 11+ icon style).
# Requires ImageMagick (magick), sips, iconutil.
set -euo pipefail
cd "$(dirname "$0")"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Trim transparent margins from the flame; scale so it is 650px tall on the 1024 canvas.
magick logo.png -trim +repage "$TMP/flame.png"
magick "$TMP/flame.png" -resize x650 "$TMP/flame.png"
FW=$(magick "$TMP/flame.png" -format '%w' info:)
FH=$(magick "$TMP/flame.png" -format '%h' info:)

# Dark charcoal gradient masked to a squircle (corner radius 185 of 1024).
magick -size 1024x1024 gradient:'#2D2D30'-'#1A1A1D' \
  \( -size 1024x1024 xc:none -fill white -draw 'roundrectangle 0,0 1023,1023 185,185' \) \
  -compose CopyOpacity -composite "$TMP/bg.png"

OX=$(( (1024 - FW) / 2 ))
OY=$(( (1024 - FH) / 2 ))
magick "$TMP/bg.png" "$TMP/flame.png" -geometry "+${OX}+${OY}" -compose Over \
  -composite AppIcon-1024.png

# Render every macOS icon size.
rm -rf AppIcon.iconset
mkdir -p AppIcon.iconset
sips -z 16 16   AppIcon-1024.png --out AppIcon.iconset/icon_16x16.png      >/dev/null
sips -z 32 32   AppIcon-1024.png --out AppIcon.iconset/icon_16x16@2x.png   >/dev/null
sips -z 32 32   AppIcon-1024.png --out AppIcon.iconset/icon_32x32.png      >/dev/null
sips -z 64 64   AppIcon-1024.png --out AppIcon.iconset/icon_32x32@2x.png   >/dev/null
sips -z 128 128 AppIcon-1024.png --out AppIcon.iconset/icon_128x128.png    >/dev/null
sips -z 256 256 AppIcon-1024.png --out AppIcon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 AppIcon-1024.png --out AppIcon.iconset/icon_256x256.png    >/dev/null
sips -z 512 512 AppIcon-1024.png --out AppIcon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 AppIcon-1024.png --out AppIcon.iconset/icon_512x512.png    >/dev/null
cp AppIcon-1024.png AppIcon.iconset/icon_512x512@2x.png

iconutil -c icns AppIcon.iconset -o AppIcon.icns
echo "Built assets/AppIcon.icns ($(stat -f '%z' AppIcon.icns) bytes)"
