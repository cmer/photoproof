#!/usr/bin/env bash
# Build PhotoProof for the current Conductor workspace, launch it, and keep
# the script attached so Conductor's Stop button can terminate the app.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="PhotoProof.xcodeproj"
SCHEME="PhotoProof"
CONFIG="Debug"
DERIVED_DATA="$ROOT_DIR/.context/DerivedData"

mkdir -p "$DERIVED_DATA"

echo "Building $SCHEME ($CONFIG) for Conductor..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

APP_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}')

APP_PATH="$APP_DIR/$SCHEME.app"
APP_EXEC="$APP_PATH/Contents/MacOS/$SCHEME"

if [[ ! -x "$APP_EXEC" ]]; then
    echo "Build succeeded but couldn't locate executable: $APP_EXEC" >&2
    exit 1
fi

cleanup() {
    if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        echo "Stopping $SCHEME..."
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM

echo "Launching $APP_PATH..."
"$APP_EXEC" &
APP_PID=$!

echo "$SCHEME is running with PID $APP_PID. Stop this Conductor run to quit it."
wait "$APP_PID"
