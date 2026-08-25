#!/usr/bin/env bash
# Builds Tappi.app. Pass --install to copy it into /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
APP="dist/Tappi.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Tappi"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tappi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# TCC (Accessibility, Screen Recording) keys off the code signature, and an ad-hoc
# signature is identified by the hash of the binary — so every rebuild invalidates
# the granted permissions. Prefer any real signing identity over ad-hoc; run
# ./setup-signing.sh once to create a local one.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "Tappi Local Signing"; then
    IDENTITY="Tappi Local Signing"
  else
    IDENTITY="-"
    echo "!!  signing ad-hoc: macOS will forget granted permissions on every rebuild."
    echo "!!  run ./setup-signing.sh once to avoid that."
  fi
fi
echo "==> codesign (identity: $IDENTITY)"
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign "$IDENTITY" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> installing to /Applications"
  pkill -x Tappi || true
  rm -rf /Applications/Tappi.app
  cp -R "$APP" /Applications/Tappi.app
  open /Applications/Tappi.app
  echo "==> running from /Applications/Tappi.app"
else
  echo "==> done: $APP"
fi
