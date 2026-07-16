#!/usr/bin/env bash
# Build PhotoProof in Release configuration and copy the bundle to ./build/.
#
# This produces an unsigned optimized bundle suitable for local use and as the
# input to release.sh, which signs, notarizes, staples, and packages it.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="PhotoProof.xcodeproj"
SCHEME="PhotoProof"
CONFIG="Release"
OUT_DIR="build"

mkdir -p "$OUT_DIR"

echo "→ Building $SCHEME ($CONFIG)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

APP_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}')
SRC_APP="$APP_DIR/$SCHEME.app"

if [ ! -d "$SRC_APP" ]; then
    echo "✗ Build succeeded but couldn't locate $SRC_APP"
    exit 1
fi

DEST="$OUT_DIR/$SCHEME.app"
rm -rf "$DEST"
cp -R "$SRC_APP" "$DEST"

SIZE=$(du -sh "$DEST" | awk '{print $1}')
echo "✓ Built: $DEST ($SIZE)"
echo "  Drag it to /Applications, or:"
echo "  open \"$DEST\""
