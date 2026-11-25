#!/bin/bash
# Build ZAD Font thành file .app rồi mở luôn.
set -e
cd "$(dirname "$0")"

echo "== Swift trên máy =="
swift --version

swift build -c release

APP="build/ZAD Font.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ZADFont "$APP/Contents/MacOS/ZADFont"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ZADFont</string>
  <key>CFBundleIdentifier</key><string>com.zad.font</string>
  <key>CFBundleName</key><string>ZAD Font</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "== Xong: $APP =="

# bash build.sh install: chép app vào /Applications
if [ "$1" = "install" ]; then
  rm -rf "/Applications/ZAD Font.app"
  ditto "$APP" "/Applications/ZAD Font.app"
  APP="/Applications/ZAD Font.app"
  echo "== Đã cài vào $APP =="
fi

if [ -z "$CI" ]; then open "$APP"; fi
