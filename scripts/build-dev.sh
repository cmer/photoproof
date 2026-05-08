#!/usr/bin/env bash
# Build PhotoProof in Debug configuration and launch it.
# Use this for day-to-day development — fast build, ad-hoc signing, no archive.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="PhotoProof.xcodeproj"
SCHEME="PhotoProof"
CONFIG="Debug"

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
APP_PATH="$APP_DIR/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ Build succeeded but couldn't locate $APP_PATH"
    exit 1
fi

echo "✓ Built: $APP_PATH"
echo "→ Launching…"
open "$APP_PATH"
