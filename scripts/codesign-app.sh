#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/App.app" >&2
    exit 2
fi

APP_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$APP_DIR" ]; then
    echo "App bundle not found: $APP_DIR" >&2
    exit 1
fi

# A certificate-backed signature gives macOS a stable designated requirement,
# so TCC permissions survive normal rebuilds. Set CODESIGN_IDENTITY to override
# automatic selection (for example, to use a Developer ID certificate).
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"
    echo "Warning: no Apple Development identity found; using ad-hoc signing."
else
    echo "Signing with: $SIGNING_IDENTITY"
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" \
    "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -dvv "$APP_DIR" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)='
