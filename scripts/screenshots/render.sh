#!/usr/bin/env bash
# Regenerates the README images in docs/screenshots/ — English and German — from
# Tappi's own drawing code, offscreen, with invented demo windows.
#
#   scripts/screenshots/render.sh
#
# It never captures the screen, never lists real windows and never touches
# ~/Library/Application Support/Tappi: the app's sources are copied into a
# temporary folder and `Settings.directory` is redirected there before compiling.
# Nothing here is part of the app build.
#
# Environment: OUT (default docs/screenshots), WORK (default a fresh temp folder,
# removed afterwards unless KEEP_WORK=1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-$ROOT/docs/screenshots}"
OWN_WORK=0
if [[ -z "${WORK:-}" ]]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/tappi-screenshots.XXXXXX")"
  OWN_WORK=1
fi
SRC="$WORK/src"
APP="$WORK/TappiScreenshots.app"
SUPPORT="$WORK/support"
rm -rf "$SRC" "$APP" "$SUPPORT"
mkdir -p "$SRC" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SUPPORT" "$OUT"

echo "==> copying app sources (without main.swift)"
for file in "$ROOT"/Sources/Tappi/*.swift; do
  [[ "$(basename "$file")" == "main.swift" ]] || cp "$file" "$SRC/"
done

echo "==> redirecting Settings.directory into $SUPPORT"
perl -0pi -e 's/\QFileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]\E/URL(fileURLWithPath: ProcessInfo.processInfo.environment["TAPPI_SCREENSHOT_SUPPORT"]!, isDirectory: true)/' \
  "$SRC/Settings.swift"
if grep -q "applicationSupportDirectory\|homeDirectory\|NSHomeDirectory" "$SRC"/*.swift \
   || ! grep -q TAPPI_SCREENSHOT_SUPPORT "$SRC/Settings.swift"; then
  echo "!!  could not redirect Settings.directory — Settings.swift changed, update render.sh" >&2
  exit 1
fi

echo "==> compiling harness"
swiftc -swift-version 5 -O -suppress-warnings -target "$(uname -m)-apple-macos14" \
  -o "$APP/Contents/MacOS/TappiScreenshots" \
  "$SRC"/*.swift "$ROOT/scripts/screenshots/main.swift" \
  -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit \
  -framework CoreGraphics -framework QuartzCore

# A bundle of its own (separate identifier, no shared defaults with the real app),
# carrying the .lproj folders so the app's Localizer finds its strings.
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>de.tappi.Tappi.screenshots</string>
	<key>CFBundleExecutable</key>
	<string>TappiScreenshots</string>
	<key>CFBundleName</key>
	<string>TappiScreenshots</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

for lang in en de; do
  echo "==> rendering switcher ($lang)"
  TAPPI_SCREENSHOT_SUPPORT="$SUPPORT" "$APP/Contents/MacOS/TappiScreenshots" \
    --out "$OUT" --lang "$lang" -AppleLanguages "($lang)"
done

echo "==> rendering icon"
swift "$ROOT/scripts/generate-icon.swift" --png "$OUT/icon.png" 512

if [[ "$OWN_WORK" == 1 && "${KEEP_WORK:-0}" != 1 ]]; then
  rm -rf "$WORK"
fi
echo "==> done: $OUT"
