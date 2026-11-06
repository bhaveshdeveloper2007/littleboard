#!/bin/sh
# Build Littleboard in release mode, package the app bundle, and open it.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  export DEVELOPER_DIR
fi

echo "==> Building (release)"
swift build -c release

EXECUTABLE="$ROOT/.build/out/Products/Release/Littleboard"
if [ ! -x "$EXECUTABLE" ]; then
  EXECUTABLE="$ROOT/.build/arm64-apple-macosx/release/Littleboard"
fi
if [ ! -x "$EXECUTABLE" ]; then
  echo "error: release binary not found" >&2
  exit 1
fi

echo "==> Packaging build/Littleboard.app"
APP="$ROOT/build/Littleboard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/Littleboard"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Littleboard</string>
  <key>CFBundleIdentifier</key><string>org.rea.examples.littleboard</string>
  <key>CFBundleName</key><string>Littleboard</string>
  <key>CFBundleDisplayName</key><string>Littleboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Littleboard uses your location to show local weather in the weather widget.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Littleboard shows your upcoming calendar events in the calendar widget.</string>
  <key>NSCalendarsUsageDescription</key><string>Littleboard shows your upcoming calendar events in the calendar widget.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Littleboard lists connected Bluetooth accessories and their batteries in the Devices widget.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign -f -s - "$APP" 2>/dev/null || true

echo "==> Opening Littleboard"
open "$APP"
echo "==> Done. Add widgets from the Littleboard library window."
